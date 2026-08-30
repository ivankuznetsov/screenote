# frozen_string_literal: true

require "test_helper"

module ImageAttachments
  class CreateApiCommentTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    self.use_transactional_tests = false

    setup do
      cleanup_created_comments
      clear_enqueued_jobs
      require_vips!
      @annotation = annotations(:point_annotation)
      @project = projects(:alice_project)
      @bytes = image_bytes
      @key = "test_image_comment_key_1234567890"
    end

    teardown do
      cleanup_created_comments
      clear_enqueued_jobs
    end

    test "creates one user-authored comment and ready submitted attachment" do
      principal = AuthenticatedPrincipal.for_user(users(:alice))

      assert_enqueued_jobs 1, only: ImageAttachmentThumbnailJob do
        assert_difference [ "AnnotationComment.count", "ImageAttachment.count", "ActiveStorage::Blob.count" ], 1 do
          result = create_comment(principal:)

          assert_predicate result, :created?
          assert_equal "created", result.operation
          assert_equal "Use this layout", result.comment.body
          assert_equal users(:alice), result.comment.user
          assert_nil result.comment.api_key

          attachment = result.attachment
          assert_equal result.comment, attachment.annotation_comment
          assert_equal users(:alice), attachment.user
          assert_equal @project, attachment.project
          assert_predicate attachment, :submitted?
          assert_predicate attachment, :state_ready?
          assert_predicate attachment.image, :attached?
          assert_equal result.comment.idempotency_fingerprint, attachment.client_key
          assert_equal @bytes, attachment.image.download
        end
      end
    end

    test "api key remains the comment actor and its active issuer owns the attachment" do
      key = api_keys(:alice_key)
      principal = AuthenticatedPrincipal.for_api_key(key)
      project_memberships(:bob_member_of_alice_project).update!(role: :owner)
      project_memberships(:alice_owns_alice_project).destroy!

      result = create_comment(principal:)

      assert_equal key, result.comment.api_key
      assert_nil result.comment.user
      assert_equal key.issued_by_user, result.attachment.user
      assert_equal @project, result.attachment.project
    end

    test "identical replay returns the same complete pair without staging another blob or job" do
      principal = AuthenticatedPrincipal.for_user(users(:alice))
      first = create_comment(principal:)

      assert_no_enqueued_jobs only: ImageAttachmentThumbnailJob do
        assert_no_difference [ "AnnotationComment.count", "ImageAttachment.count", "ActiveStorage::Blob.count" ] do
          replay = create_comment(principal:)

          assert_predicate replay, :replayed?
          assert_equal "replayed", replay.operation
          assert_equal first.comment.id, replay.comment.id
          assert_equal first.attachment.id, replay.attachment.id
        end
      end
    end

    test "same scoped key with changed body or image conflicts without another pair" do
      principal = AuthenticatedPrincipal.for_user(users(:alice))
      create_comment(principal:)

      assert_no_difference [ "AnnotationComment.count", "ImageAttachment.count", "ActiveStorage::Blob.count" ] do
        body_error = assert_raises(ImageAttachments::Error) do
          create_comment(principal:, body: "Different instruction")
        end
        assert_equal "idempotency_conflict", body_error.code

        image_error = assert_raises(ImageAttachments::Error) do
          create_comment(principal:, bytes: image_bytes(width: 9))
        end
        assert_equal "idempotency_conflict", image_error.code
      end
    end

    test "the same literal key is independent across actors and annotations" do
      alice = AuthenticatedPrincipal.for_user(users(:alice))
      bob = AuthenticatedPrincipal.for_user(users(:bob))
      first = create_comment(principal: alice)
      second = create_comment(principal: bob)
      third = create_comment(principal: alice, annotation: annotations(:region_annotation))

      assert_equal 3, [ first, second, third ].map(&:comment).map(&:id).uniq.size
      assert_equal 3, [ first, second, third ].map(&:comment).map(&:idempotency_fingerprint).uniq.size
    end

    test "invalid body and project handoff leave no comment attachment or blob" do
      principal = AuthenticatedPrincipal.for_user(users(:alice))

      assert_no_difference [ "AnnotationComment.count", "ImageAttachment.count", "ActiveStorage::Blob.count" ] do
        assert_raises(ActiveRecord::RecordInvalid) { create_comment(principal:, body: "") }
        assert_raises(ArgumentError) do
          create_comment(principal:, project: projects(:bob_project), idempotency_key: "different_project_key_1234")
        end
      end
    end

    test "a storage association failure rolls back the pair and purges the staged blob" do
      principal = AuthenticatedPrincipal.for_user(users(:alice))
      original = ActiveStorage::Attached::One.instance_method(:attach)

      ActiveStorage::Attached::One.define_method(:attach) do |*|
        raise ActiveRecord::RecordInvalid.new(record)
      end

      assert_no_difference [ "AnnotationComment.count", "ImageAttachment.count", "ActiveStorage::Blob.count" ] do
        assert_raises(ActiveRecord::RecordInvalid) { create_comment(principal:) }
      end
    ensure
      ActiveStorage::Attached::One.define_method(:attach, original) if original
    end

    test "adapter-specific thumbnail enqueue failure after commit keeps and returns the complete pair" do
      principal = AuthenticatedPrincipal.for_user(users(:alice))
      original = ImageAttachmentThumbnailJob.method(:perform_later)
      adapter_error = Class.new(StandardError)
      ImageAttachmentThumbnailJob.define_singleton_method(:perform_later) do |*|
        raise adapter_error, "queue unavailable"
      end

      assert_difference [ "AnnotationComment.count", "ImageAttachment.count", "ActiveStorage::Blob.count" ], 1 do
        result = create_comment(principal:)

        assert_predicate result, :created?
        assert_predicate result.attachment.image, :attached?
      end
    ensure
      ImageAttachmentThumbnailJob.define_singleton_method(:perform_later, original) if original
    end

    test "outer transaction commit adopts the object and warms only after commit" do
      principal = AuthenticatedPrincipal.for_user(users(:alice))
      result = nil

      ActiveRecord::Base.transaction do
        result = create_comment(principal:)

        assert_empty enqueued_jobs
        assert result.attachment.image.blob.service.exist?(result.attachment.image.blob.key)
      end

      assert_enqueued_jobs 1, only: ImageAttachmentThumbnailJob
      assert_predicate result.comment.reload, :persisted?
      assert_predicate result.attachment.reload.image, :attached?
    end

    test "outer transaction rollback removes the staged object and warming job" do
      principal = AuthenticatedPrincipal.for_user(users(:alice))
      before = [ AnnotationComment.count, ImageAttachment.count, ActiveStorage::Blob.count ]
      blob = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        result = create_comment(principal:)
        blob = result.attachment.image.blob

        assert blob.service.exist?(blob.key)
        assert_empty enqueued_jobs
        raise ActiveRecord::Rollback
      end

      assert_equal before, [ AnnotationComment.count, ImageAttachment.count, ActiveStorage::Blob.count ]
      assert_not blob.service.exist?(blob.key)
      assert_empty enqueued_jobs
    end

    test "a supplied image digest must match the verified bytes" do
      principal = AuthenticatedPrincipal.for_user(users(:alice))

      assert_no_difference [ "AnnotationComment.count", "ImageAttachment.count", "ActiveStorage::Blob.count" ] do
        error = assert_raises(ImageAttachments::Error) do
          create_comment(principal:, expected_sha256: "0" * 64)
        end
        assert_equal "content_digest_mismatch", error.code
      end
    end

    private

    def cleanup_created_comments
      AnnotationComment.where.not(idempotency_fingerprint: nil).find_each do |comment|
        comment.image_attachments.each do |attachment|
          attachment.image.purge if attachment.image.attached?
        end
        comment.destroy!
      end
      ActiveStorage::Blob.unattached.find_each(&:purge)
    end

    def create_comment(principal:, annotation: @annotation, project: @project, body: "Use this layout", bytes: @bytes,
      idempotency_key: @key, expected_sha256: nil)
      ImageAttachments::CreateApiComment.call(
        annotation:,
        project:,
        principal:,
        body:,
        io: StringIO.new(bytes),
        idempotency_key:,
        expected_sha256: expected_sha256 || Digest::SHA256.hexdigest(bytes),
        declared_content_type: "image/png",
        declared_length: bytes.bytesize,
        filename: "upload.png"
      )
    end
  end
end
