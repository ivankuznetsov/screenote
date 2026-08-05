# frozen_string_literal: true

require "test_helper"

module Snapshots
  class AttachImageTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "concurrent identical uploads attach once and converge on resumable success" do
      bytes = File.binread(Rails.root.join("test/fixtures/files/test_image.png"))
      page_name = "Concurrent image #{SecureRandom.hex(6)}"
      entry = snapshot_entry(page: page_name, viewport: :desktop, seed: page_name)
      entry[:content_sha256] = Digest::SHA256.hexdigest(bytes)
      payload = snapshot_manifest_payload(entries: [ entry ])
      prepared = Queue.new
      setup_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          prepared << PrepareUpload.call(project: projects(:alice_project), payload: payload).snapshot.id
        end
      end
      setup_thread.join
      snapshot_id = prepared.pop
      image_id = Snapshot.find(snapshot_id).screenshot_images.pick(:id)
      initial_blob_count = ActiveStorage::Blob.count
      ready = Queue.new
      start = Queue.new
      results = Queue.new
      errors = Queue.new
      clear_enqueued_jobs

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            results << AttachImage.call(
              image: ScreenshotImage.find(image_id),
              io: StringIO.new(bytes),
              declared_content_type: "image/png",
              declared_length: bytes.bytesize
            )
          rescue StandardError => e
            errors << e
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:join)

      assert errors.empty?, errors.size.times.map { errors.pop.full_message }.join("\n")
      operations = 2.times.map { results.pop.operation }.sort
      assert_equal %w[already_uploaded uploaded], operations
      assert_equal 1, ActiveStorage::Attachment.where(record_type: "ScreenshotImage", record_id: image_id, name: "image").count
      assert_equal initial_blob_count + 1, ActiveStorage::Blob.count
      assert_equal 1, enqueued_jobs.count { |job| job[:job] == ScreenshotDimensionJob }
    ensure
      snapshot = Snapshot.find_by(id: snapshot_id)
      snapshot&.screenshots&.destroy_all
      snapshot&.destroy
      projects(:alice_project).pages.where(name: page_name).destroy_all if page_name
    end


    test "rejects an image whose header is valid but complete pixel decode is truncated" do
      screenshot = pages(:alice_page).screenshots.create!(title: "Truncated image #{SecureRandom.hex(4)}")
      image = screenshot.screenshot_images.create!(viewport: :desktop)
      bytes = png_header(width: 16, height: 16)

      error = assert_raises(AttachImage::Error) do
        AttachImage.call(
          image: image,
          io: StringIO.new(bytes),
          declared_content_type: "image/png",
          declared_length: bytes.bytesize
        )
      end

      assert_equal "invalid_image", error.code
      assert_not image.reload.image.attached?

      valid_bytes = File.binread(Rails.root.join("test/fixtures/files/test_image.png"))
      result = AttachImage.call(
        image: image,
        io: StringIO.new(valid_bytes),
        declared_content_type: "image/png",
        declared_length: valid_bytes.bytesize
      )
      assert_equal "uploaded", result.operation
    ensure
      screenshot&.destroy!
    end

    test "storage upload failure leaves no attachment blob or temporary file" do
      screenshot = pages(:alice_page).screenshots.create!(title: "Storage failure #{SecureRandom.hex(4)}")
      image = screenshot.screenshot_images.create!(viewport: :desktop)
      bytes = File.binread(Rails.root.join("test/fixtures/files/test_image.png"))
      upload_tempfiles = Rails.root.join("tmp/screenote-upload-#{Process.pid}-*.image")
      service = ActiveStorage::Blob.service
      original_upload = service.method(:upload)
      written_key = nil

      assert_no_difference [ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
        service.define_singleton_method(:upload) do |*arguments, **options|
          written_key = arguments.first
          original_upload.call(*arguments, **options)
          raise IOError, "storage failed after writing"
        end
        assert_raises(IOError) do
          AttachImage.call(
            image: image,
            io: StringIO.new(bytes),
            declared_content_type: "image/png",
            declared_length: bytes.bytesize
          )
        end
      end

      assert_not image.reload.image.attached?
      assert_not_nil written_key
      assert_not service.exist?(written_key)
      assert_empty Dir.glob(upload_tempfiles)
    ensure
      service&.define_singleton_method(:upload, original_upload) if original_upload
      screenshot&.destroy!
    end

    test "rolling back an outer transaction removes its staged storage object" do
      screenshot = pages(:alice_page).screenshots.create!(title: "Storage rollback #{SecureRandom.hex(4)}")
      image = screenshot.screenshot_images.create!(viewport: :desktop)
      bytes = File.binread(Rails.root.join("test/fixtures/files/test_image.png"))
      blob = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        result = AttachImage.call(
          image: image,
          io: StringIO.new(bytes),
          declared_content_type: "image/png",
          declared_length: bytes.bytesize
        )
        blob = result.image.image.blob
        assert blob.service.exist?(blob.key)

        raise ActiveRecord::Rollback
      end

      assert_not blob.service.exist?(blob.key)
      assert_not image.reload.image.attached?
    ensure
      screenshot&.destroy!
    end

    test "rolling back a replacement preserves the old attachment and removes the staged object" do
      screenshot = pages(:alice_page).screenshots.create!(title: "Replacement rollback #{SecureRandom.hex(4)}")
      image = screenshot.screenshot_images.create!(viewport: :desktop)
      bytes = File.binread(Rails.root.join("test/fixtures/files/test_image.png"))
      AttachImage.call(
        image: image,
        io: StringIO.new(bytes),
        declared_content_type: "image/png",
        declared_length: bytes.bytesize,
        schedule_processing: false
      )
      old_blob = image.reload.image.blob
      staged_blob = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        result = AttachImage.call(
          image: image,
          io: StringIO.new(bytes),
          declared_content_type: "image/png",
          declared_length: bytes.bytesize,
          replace_existing: true,
          schedule_processing: false
        )
        staged_blob = result.image.image.blob
        assert_not_equal old_blob.id, staged_blob.id
        assert staged_blob.service.exist?(staged_blob.key)

        raise ActiveRecord::Rollback
      end

      assert_equal old_blob.id, image.reload.image.blob.id
      assert old_blob.service.exist?(old_blob.key)
      assert_not staged_blob.service.exist?(staged_blob.key)
    ensure
      screenshot&.destroy!
    end

    private

    def png_header(width:, height:)
      signature = "\x89PNG\r\n\x1a\n".b
      ihdr = [ width, height, 8, 0, 0, 0, 0 ].pack("NNCCCCC")
      signature + png_chunk("IHDR", ihdr) + png_chunk("IDAT", Zlib::Deflate.deflate("")) + png_chunk("IEND", "")
    end

    def png_chunk(type, data)
      [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
    end
  end
end
