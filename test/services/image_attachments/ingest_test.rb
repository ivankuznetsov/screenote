# frozen_string_literal: true

require "test_helper"

module ImageAttachments
  class IngestTest < ActiveSupport::TestCase
    setup do
      require_vips!
      @batch = build_batch
    end

    test "accepts PNG, JPEG, and WebP" do
      { "png" => "image/png", "jpg" => "image/jpeg", "webp" => "image/webp" }.each do |format, media_type|
        attachment = ingest_image(
          batch: @batch, format: format, declared_content_type: media_type, client_key: format
        )

        assert_predicate attachment, :state_ready?
        assert_equal media_type, attachment.media_type
        assert_equal 8, attachment.width
        assert_predicate attachment.byte_size, :positive?
        assert attachment.image.attached?
      end
    end

    test "accepts an extensionless upload with no declared type" do
      attachment = ingest_image(batch: @batch, declared_content_type: nil, filename: "clipboard")

      assert_predicate attachment, :state_ready?
      assert_equal "image/png", attachment.media_type
    end

    test "generates the stored filename server side" do
      attachment = ingest_image(batch: @batch, filename: "../../etc/passwd.png")

      assert_equal "image-attachment-#{attachment.id}.png", attachment.image.blob.filename.to_s
    end

    test "rejects a GIF" do
      error = assert_raises(ImageAttachments::Error) do
        ingest_image(batch: @batch, bytes: file_fixture("test_invalid.gif").binread, declared_content_type: nil)
      end

      assert_equal "invalid_image", error.code
    end

    test "rejects SVG bytes" do
      error = assert_raises(ImageAttachments::Error) do
        ingest_image(batch: @batch, bytes: "<svg xmlns='http://www.w3.org/2000/svg'></svg>", declared_content_type: nil)
      end

      assert_equal "invalid_image", error.code
    end

    test "rejects a declared type that does not match the bytes" do
      error = assert_raises(ImageAttachments::Error) do
        ingest_image(batch: @batch, format: "png", declared_content_type: "image/webp")
      end

      assert_equal "content_type_mismatch", error.code
    end

    test "rejects an extension that does not match the bytes" do
      error = assert_raises(ImageAttachments::Error) do
        ingest_image(batch: @batch, format: "png", declared_content_type: nil, filename: "spoof.webp")
      end

      assert_equal "extension_mismatch", error.code
    end

    test "rejects truncated image bytes" do
      truncated = image_bytes(format: "png").byteslice(0, 40)

      error = assert_raises(ImageAttachments::Error) do
        ingest_image(batch: @batch, bytes: truncated, declared_content_type: "image/png")
      end

      assert_equal "invalid_image", error.code
    end

    test "rejects an empty upload" do
      error = assert_raises(ImageAttachments::Error) do
        ingest_image(batch: @batch, bytes: "", declared_content_type: "image/png")
      end

      assert_equal "empty_file", error.code
    end

    test "rejects a declared length over the per-file limit" do
      error = assert_raises(ImageAttachments::Error) do
        ingest_image(batch: @batch, declared_length: ImageAttachment::MAX_FILE_SIZE + 1)
      end

      assert_equal "file_too_large", error.code
    end

    test "rejects a stream that exceeds the per-file limit" do
      stub_const(ImageAttachment, :MAX_FILE_SIZE, 32) do
        error = assert_raises(ImageAttachments::Error) do
          ingest_image(batch: @batch)
        end

        assert_equal "file_too_large", error.code
      end
    end

    test "rejects a sixth file" do
      ImageAttachment::MAX_FILES.times { |index| ingest_image(batch: @batch, client_key: "file-#{index}") }

      error = assert_raises(ImageAttachments::Error) { ingest_image(batch: @batch, client_key: "file-5") }

      assert_equal "too_many_files", error.code
      assert_equal ImageAttachment::MAX_FILES, @batch.image_attachments.count
    end

    # Removal leaves a tombstone that keeps the client key reserved, but the
    # composer no longer shows that row. Counting it against the ceiling would
    # wedge the batch after the first replacement.
    test "accepts a replacement after a removal at the file ceiling" do
      ImageAttachment::MAX_FILES.times { |index| ingest_image(batch: @batch, client_key: "file-#{index}") }
      RemoveAttachment.call(batch: @batch, client_key: "file-0")

      replacement = ingest_image(batch: @batch, client_key: "replacement")

      assert_predicate replacement, :state_ready?
      assert_equal ImageAttachment::MAX_FILES, @batch.image_attachments.active_drafts.count
    end

    test "still rejects a sixth active file after a removal" do
      ImageAttachment::MAX_FILES.times { |index| ingest_image(batch: @batch, client_key: "file-#{index}") }
      RemoveAttachment.call(batch: @batch, client_key: "file-0")
      ingest_image(batch: @batch, client_key: "replacement")

      error = assert_raises(ImageAttachments::Error) { ingest_image(batch: @batch, client_key: "one-too-many") }

      assert_equal "too_many_files", error.code
    end

    test "rejects a batch over the total byte budget" do
      ingest_image(batch: @batch, client_key: "first")

      stub_const(ImageAttachment, :MAX_TOTAL_BYTES, 1) do
        error = assert_raises(ImageAttachments::Error) { ingest_image(batch: @batch, client_key: "second") }

        assert_equal "batch_too_large", error.code
      end
      assert_predicate @batch.image_attachments.find_by(client_key: "second"), :state_failed?
    end

    test "rejects an expired batch" do
      @batch.update_columns(last_activity_at: 25.hours.ago, expires_at: 1.minute.ago)

      error = assert_raises(ImageAttachments::Error) { ingest_image(batch: @batch) }

      assert_equal "batch_unusable", error.code
    end

    test "a failed upload keeps an observable row that occupies a slot" do
      assert_raises(ImageAttachments::Error) do
        ingest_image(batch: @batch, bytes: "not an image", declared_content_type: nil, client_key: "broken")
      end

      row = @batch.image_attachments.sole
      assert_predicate row, :state_failed?
      assert_equal "invalid_image", row.failure_code
      assert_not row.image.attached?
    end

    test "retry with the same client key reuses the slot" do
      assert_raises(ImageAttachments::Error) do
        ingest_image(batch: @batch, bytes: "not an image", declared_content_type: nil, client_key: "retry")
      end

      attachment = ingest_image(batch: @batch, client_key: "retry")

      assert_equal 1, @batch.image_attachments.count
      assert_predicate attachment, :state_ready?
      assert_nil attachment.failure_code
    end

    test "a busy decoder is retryable rather than a permanent failure" do
      ImageDecoding::Guard::CONCURRENCY.times.map { ImageDecoding::Guard::SEMAPHORE.try_acquire(1, 0) }

      error = assert_raises(ImageAttachments::Error) { ingest_image(batch: @batch) }

      assert_equal "decoder_busy", error.code
      assert_predicate error, :retryable?
      assert_equal :service_unavailable, error.status
    ensure
      ImageDecoding::Guard::CONCURRENCY.times { ImageDecoding::Guard::SEMAPHORE.release }
    end

    test "a successful upload extends the batch activity window" do
      @batch.update_columns(last_activity_at: 3.hours.ago, expires_at: 21.hours.from_now)

      ingest_image(batch: @batch)

      assert_operator @batch.reload.expires_at, :>, 23.hours.from_now
    end

    test "rejects images beyond the pixel budget" do
      stub_const(ImageAttachment, :MAX_PIXELS, 4) do
        error = assert_raises(ImageAttachments::Error) { ingest_image(batch: @batch) }

        assert_equal "image_pixels_too_large", error.code
      end
    end

    test "replaying a finished client key returns the same row and keeps its blob" do
      attachment = ingest_image(batch: @batch, client_key: "lost-response")
      blob_id = attachment.image.blob.id
      blobs = ActiveStorage::Blob.count

      replayed = ingest_image(batch: @batch, client_key: "lost-response")

      assert_equal attachment.id, replayed.id
      assert_predicate replayed, :state_ready?
      assert_equal blob_id, replayed.reload.image.blob.id
      assert_equal 1, @batch.image_attachments.count
      assert_equal blobs, ActiveStorage::Blob.count
    end

    test "the outstanding draft byte ceiling is rechecked when an upload commits" do
      parked = build_batch(user: @batch.user, project: @batch.project)
      parked.image_attachments.create!(
        user: @batch.user, project: @batch.project, client_key: "parked", state: :ready,
        media_type: "image/png", width: 1, height: 1, byte_size: 4.kilobytes
      )

      stub_const(ImageAttachmentBatch, :MAX_OUTSTANDING_DRAFT_BYTES, 4.kilobytes) do
        error = assert_raises(ImageAttachments::Error) { ingest_image(batch: @batch) }

        assert_equal "draft_storage_exhausted", error.code
      end

      assert_predicate @batch.image_attachments.sole, :state_failed?
      assert_not @batch.image_attachments.sole.image.attached?
    end

    # An aborted attempt shares its slot with the retry that supersedes it, so a
    # late failure from the disconnected attempt must not un-ready the row the
    # retry already finished and block the post with `attachments_not_ready`.
    test "a late failure cannot un-ready a row another attempt finished" do
      attachment = ingest_image(batch: @batch, client_key: "superseded")

      ImageAttachments::Ingest
        .new(batch: @batch, io: StringIO.new(""), client_key: "superseded")
        .send(:record_failure, attachment, ImageAttachments::Error.new(code: "upload_failed"))

      attachment.reload
      assert_predicate attachment, :state_ready?
      assert_nil attachment.failure_code
    end

    test "a commit refuses to bind bytes onto a row that was removed" do
      attachment = ingest_image(batch: @batch, client_key: "removed")
      ImageAttachments::RemoveAttachment.call(batch: @batch, attachment_id: attachment.id)
      prepared = ImageAttachments::PrepareUpload.call(
        io: StringIO.new(image_bytes), declared_content_type: "image/png"
      )

      error = assert_raises(ImageAttachments::Error) do
        ImageAttachments::Ingest.new(batch: @batch, io: StringIO.new(image_bytes), client_key: "removed")
          .send(:commit!, attachment, prepared)
      end

      assert_equal "attachment_removed", error.code
      assert_equal :not_found, error.status
      assert_predicate @batch.image_attachments.reload.sole, :removal_tombstone?
      assert_not @batch.image_attachments.sole.image.attached?
    ensure
      prepared&.cleanup
    end

    test "an unexpected IO failure still answers with a machine code" do
      failing_io = Object.new
      def failing_io.read(*)
        raise IOError, "the upload socket went away"
      end

      error = assert_raises(ImageAttachments::Error) do
        ImageAttachments::Ingest.call(
          batch: @batch, io: failing_io, client_key: "broken", declared_content_type: "image/png"
        )
      end

      assert_equal "upload_failed", error.code
      assert_equal :internal_server_error, error.status
      assert_predicate error, :retryable?
      assert_equal "upload_failed", @batch.image_attachments.sole.failure_code
    end
  end
end
