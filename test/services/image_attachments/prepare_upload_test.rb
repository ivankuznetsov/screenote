# frozen_string_literal: true

require "test_helper"

module ImageAttachments
  class PrepareUploadTest < ActiveSupport::TestCase
    setup do
      require_vips!
      @bytes = image_bytes
    end

    test "verifies supported image bytes without staging storage" do
      { "png" => "image/png", "jpg" => "image/jpeg", "webp" => "image/webp" }.each do |format, media_type|
        bytes = image_bytes(format: format)
        prepared = prepare(bytes:, declared_content_type: media_type, filename: "upload.#{format}")

        assert_equal media_type, prepared.media_type
        assert_equal bytes.bytesize, prepared.byte_size
        assert_equal Digest::SHA256.hexdigest(bytes), prepared.sha256
        assert_equal [ 8, 8 ], [ prepared.width, prepared.height ]
        assert_nil prepared.blob
        assert_equal bytes, prepared.read
      ensure
        prepared&.cleanup
      end
    end

    test "accepts the exact byte limit and rejects one byte beyond it" do
      stub_const(ImageAttachment, :MAX_FILE_SIZE, @bytes.bytesize) do
        prepared = prepare
        assert_equal @bytes.bytesize, prepared.byte_size
        prepared.cleanup
      end

      stub_const(ImageAttachment, :MAX_FILE_SIZE, @bytes.bytesize - 1) do
        error = assert_raises(ImageAttachments::Error) { prepare }
        assert_equal "file_too_large", error.code
      end
    end

    test "stages only on request and cleanup purges an unadopted blob" do
      prepared = prepare
      blob = prepared.stage!(record: projects(:alice_project), filename: "image-attachment-test.png")

      assert_equal blob, prepared.blob
      assert blob.persisted?
      assert blob.service.exist?(blob.key)

      prepared.cleanup

      assert_not ActiveStorage::Blob.exists?(blob.id)
      assert_not blob.service.exist?(blob.key)
    end

    test "adoption transfers blob ownership while cleanup still closes the tempfile" do
      prepared = prepare
      blob = prepared.stage!(record: projects(:alice_project), filename: "image-attachment-test.png")
      path = prepared.path

      prepared.adopt_blob!
      prepared.cleanup

      assert ActiveStorage::Blob.exists?(blob.id)
      assert blob.service.exist?(blob.key)
      assert_not File.exist?(path)
    ensure
      blob&.purge
    end

    test "rejects mismatched and malformed input with stable attachment errors" do
      mismatch = assert_raises(ImageAttachments::Error) do
        prepare(declared_content_type: "image/webp", filename: "upload.webp")
      end
      assert_equal "content_type_mismatch", mismatch.code

      malformed = assert_raises(ImageAttachments::Error) do
        prepare(bytes: @bytes.byteslice(0, 40))
      end
      assert_equal "invalid_image", malformed.code
    end

    private

    def prepare(bytes: @bytes, declared_content_type: "image/png", filename: "upload.png")
      ImageAttachments::PrepareUpload.call(
        io: StringIO.new(bytes),
        declared_content_type: declared_content_type,
        declared_length: bytes.bytesize,
        filename: filename,
        decoder_key: "prepare-upload-test"
      )
    end
  end
end
