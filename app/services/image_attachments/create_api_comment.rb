# frozen_string_literal: true

require "digest"

module ImageAttachments
  # Creates one API-authored comment and one submitted attachment as a single
  # idempotent domain operation.
  class CreateApiComment
    IDEMPOTENCY_KEY = /\A[A-Za-z0-9_-]{16,64}\z/
    SHA256 = /\A[0-9a-f]{64}\z/

    Result = Data.define(:comment, :attachment, :operation) do
      def created?
        operation == "created"
      end

      def replayed?
        operation == "replayed"
      end
    end

    class << self
      def call(**kwargs)
        new(**kwargs).call
      end
    end

    def initialize(annotation:, project:, principal:, body:, io:, idempotency_key:, expected_sha256: nil,
      declared_content_type: nil, declared_length: nil, filename: nil)
      @annotation = annotation
      @project = project
      @principal = principal
      @body = body.to_s
      @io = io
      @idempotency_key = idempotency_key.to_s
      @expected_sha256 = expected_sha256.to_s.presence
      @declared_content_type = declared_content_type
      @declared_length = declared_length
      @filename = filename
    end

    def call
      validate_handoff!
      validate_idempotency_key!
      prepared = PrepareUpload.call(
        io:,
        declared_content_type:,
        declared_length:,
        filename:,
        decoder_key: "image_comment:#{annotation.id}"
      )
      validate_expected_digest!(prepared.sha256)
      @fingerprint = fingerprint
      @request_digest = request_digest(prepared)

      result = replay_result
      return result if result

      extension = ImageAttachment::ALLOWED_EXTENSIONS.fetch(prepared.media_type).first
      blob = prepared.stage!(
        record: annotation,
        filename: "image-comment-#{@fingerprint.first(16)}.#{extension}"
      )

      result = persist(prepared, blob)
      prepared.adopt_blob! if result.created?
      prewarm(result) if result.created?
      result
    rescue ActiveRecord::RecordNotUnique
      replay_result!
    rescue Error, ActiveRecord::RecordInvalid, ArgumentError
      raise
    rescue StandardError => error
      Screenote::Monitoring.notify(
        error,
        context: { annotation_id: annotation.id, project_id: project.id }
      )
      raise Error.new(code: "upload_failed", status: :internal_server_error)
    ensure
      prepared&.cleanup
    end

    private

    attr_reader :annotation, :project, :principal, :body, :io, :idempotency_key,
      :expected_sha256, :declared_content_type, :declared_length, :filename

    def validate_handoff!
      annotation_project_id = annotation.screenshot.page.project_id
      return if annotation_project_id == project.id && principal.project_access?(project) && principal.issuer.present?

      raise ArgumentError, "image comment authorization handoff is invalid"
    end

    def validate_idempotency_key!
      return if IDEMPOTENCY_KEY.match?(idempotency_key)

      raise Error.new(code: "invalid_idempotency_key")
    end

    def validate_expected_digest!(actual)
      return if expected_sha256.blank?
      return if SHA256.match?(expected_sha256) && ActiveSupport::SecurityUtils.secure_compare(expected_sha256, actual)

      raise Error.new(code: "content_digest_mismatch", status: :conflict)
    end

    def fingerprint
      actor_kind, actor_id = actor_identity
      framed_sha256("screenote-image-comment-fingerprint-v1", actor_kind, actor_id, annotation.id, idempotency_key)
    end

    def request_digest(prepared)
      framed_sha256("screenote-image-comment-request-v1", body, prepared.media_type, prepared.sha256)
    end

    def actor_identity
      principal.api_key? ? [ "api_key", principal.api_key.id ] : [ "user", principal.user.id ]
    end

    def framed_sha256(*fields)
      digest = Digest::SHA256.new
      fields.each do |field|
        value = field.to_s.b
        digest.update([ value.bytesize ].pack("Q>"))
        digest.update(value)
      end
      digest.hexdigest
    end

    def replay_result
      comment = AnnotationComment.find_by(idempotency_fingerprint: @fingerprint)
      return unless comment

      replay_for(comment)
    end

    def replay_result!
      comment = AnnotationComment.find_by!(idempotency_fingerprint: @fingerprint)
      replay_for(comment)
    end

    def replay_for(comment)
      raise Error.new(code: "idempotency_conflict", status: :conflict) unless
        ActiveSupport::SecurityUtils.secure_compare(comment.request_digest, @request_digest)

      Result.new(comment:, attachment: comment.image_attachments.with_media.sole, operation: "replayed")
    end

    def persist(prepared, blob)
      operation = lambda do |_attempt = nil|
        ImageAttachment.transaction do
          existing = AnnotationComment.find_by(idempotency_fingerprint: @fingerprint)
          next replay_for(existing) if existing

          comment = annotation.annotation_comments.create!(
            **principal.annotation_actor_attributes,
            body:,
            action: :comment,
            idempotency_fingerprint: @fingerprint,
            request_digest: @request_digest
          )
          attachment = comment.image_attachments.create!(
            user: principal.issuer,
            project:,
            client_key: @fingerprint,
            state: :ready,
            media_type: prepared.media_type,
            width: prepared.width,
            height: prepared.height,
            byte_size: prepared.byte_size
          )
          attachment.image.attach(blob)

          Result.new(comment:, attachment:, operation: "created")
        end
      end

      return operation.call if ApplicationRecord.connection.transaction_open?

      DatabaseRetry.call(&operation)
    end

    def prewarm(result)
      job = ImageAttachmentThumbnailJob.perform_later(result.attachment, result.attachment.image.blob.id)
      return if !job.respond_to?(:successfully_enqueued?) || job.successfully_enqueued?

      raise ActiveJob::EnqueueError, "image attachment thumbnail job was not enqueued"
    rescue ActiveJob::EnqueueError => error
      Screenote::Monitoring.notify(
        error,
        context: { annotation_comment_id: result.comment.id, image_attachment_id: result.attachment.id }
      )
    end
  end
end
