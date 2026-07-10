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
      assert_equal 1, enqueued_jobs.count { |job| job[:job] == ScreenshotDimensionJob }
    ensure
      snapshot = Snapshot.find_by(id: snapshot_id)
      snapshot&.screenshots&.destroy_all
      snapshot&.destroy
      projects(:alice_project).pages.where(name: page_name).destroy_all if page_name
    end
  end
end
