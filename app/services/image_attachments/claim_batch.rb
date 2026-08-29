# frozen_string_literal: true

module ImageAttachments
  # Binds a ready draft batch to a newly created message in one transaction.
  #
  # Lock order is fixed everywhere attachments are mutated: the batch first,
  # then its attachment rows ordered by ID. The caller's block creates the
  # parent inside that transaction, so an invalid message rolls the whole claim
  # back and leaves the ready drafts untouched.
  class ClaimBatch
    Result = Data.define(:parent, :attachments, :replayed) do
      def replayed?
        replayed
      end
    end

    class << self
      def call(**kwargs, &block)
        new(**kwargs).call(&block)
      end
    end

    def initialize(batch:, user:, project:)
      @batch = batch
      @user = user
      @project = project
    end

    def call(&parent_builder)
      raise ArgumentError, "a parent builder is required" unless parent_builder
      return Result.new(parent: parent_builder.call, attachments: [], replayed: false) if batch.nil?

      result = claim(&parent_builder)
      prewarm_variants(result) unless result.replayed?
      result
    end

    private

    attr_reader :batch, :user, :project

    def claim(&parent_builder)
      ImageAttachment.transaction do
        batch.lock!

        next replay if batch.state_claimed?

        validate_ownership!
        attachments = locked_attachments
        validate_attachments!(attachments)

        parent = parent_builder.call
        bind!(parent, attachments)
        Result.new(parent: parent, attachments: attachments, replayed: false)
      end
    end

    def replay
      Result.new(
        parent: batch.claimed_parent,
        attachments: claimed_attachments.to_a,
        replayed: true
      )
    end

    def claimed_attachments
      parent = batch.claimed_parent
      return ImageAttachment.none unless parent

      parent.image_attachments.ordered
    end

    def locked_attachments
      batch.image_attachments.ordered.lock.to_a
    end

    def validate_ownership!
      invalid!("batch_unusable") unless batch.usable?
      return if batch.user_id == user.id && batch.project_id == project.id

      invalid!("batch_not_owned")
    end

    def validate_attachments!(attachments)
      invalid!("attachments_not_ready") if attachments.any? { |attachment| !attachment.state_ready? }
      invalid!("too_many_files") if attachments.size > ImageAttachment::MAX_FILES
      return if attachments.sum { |attachment| attachment.byte_size.to_i } <= ImageAttachment::MAX_TOTAL_BYTES

      invalid!("batch_too_large")
    end

    def bind!(parent, attachments)
      column = parent_column(parent)
      now = Time.current

      attachments.each do |attachment|
        attachment.update_columns(
          column => parent.id,
          :image_attachment_batch_id => nil,
          :updated_at => now
        )
      end

      batch.update!(state: :claimed, "claimed_#{column}" => parent.id)
    end

    def parent_column(parent)
      case parent
      when Annotation then :annotation_id
      when AnnotationComment then :annotation_comment_id
      else raise ArgumentError, "#{parent.class} cannot own image attachments"
      end
    end

    # Variants are produced only for posted messages: drafts never warm, and no
    # authenticated GET is allowed to trigger decoding.
    def prewarm_variants(result)
      result.attachments.each do |attachment|
        ImageAttachmentThumbnailJob.perform_later(attachment, attachment.image.blob.id)
      end
    end

    def invalid!(code)
      raise Error.new(code: code)
    end
  end
end
