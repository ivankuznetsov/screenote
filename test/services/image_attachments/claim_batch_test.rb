# frozen_string_literal: true

require "test_helper"

module ImageAttachments
  class ClaimBatchTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      require_vips!
      @user = users(:alice)
      @project = projects(:alice_project)
      @screenshot = screenshots(:alice_screenshot)
      @batch = build_batch
    end

    test "binds every ready attachment to a new annotation" do
      first = ingest_image(batch: @batch, client_key: "a")
      second = ingest_image(batch: @batch, client_key: "b")

      result = claim { build_annotation }

      assert_not result.replayed?
      assert_equal [ first.id, second.id ], result.parent.image_attachments.pluck(:id)
      [ first, second ].each do |attachment|
        attachment.reload
        assert_predicate attachment, :submitted?
        assert_equal result.parent.id, attachment.annotation_id
        assert_nil attachment.annotation_comment_id
      end
      assert_predicate @batch.reload, :state_claimed?
      assert_equal result.parent.id, @batch.claimed_annotation_id
    end

    test "binds attachments to a reply comment" do
      ingest_image(batch: @batch)

      result = claim { annotations(:point_annotation).annotation_comments.create!(user: @user, body: "Reply") }

      attachment = result.parent.image_attachments.sole
      assert_equal result.parent.id, attachment.annotation_comment_id
      assert_nil attachment.annotation_id
    end

    test "replaying the same batch returns the already created parent" do
      ingest_image(batch: @batch)
      first = claim { build_annotation }

      assert_no_difference -> { Annotation.count } do
        replay = claim { raise "must not build a second parent" }

        assert_predicate replay, :replayed?
        assert_equal first.parent.id, replay.parent.id
        assert_equal first.attachments.map(&:id), replay.attachments.map(&:id)
      end
    end

    test "refuses to claim while any row is still uploading" do
      ingest_image(batch: @batch, client_key: "ready")
      @batch.image_attachments.create!(user: @user, project: @project, client_key: "pending")

      error = assert_raises(ImageAttachments::Error) { claim { build_annotation } }

      assert_equal "attachments_not_ready", error.code
      assert_predicate @batch.reload, :state_open?
    end

    test "refuses to claim while any row failed" do
      ingest_image(batch: @batch, client_key: "ready")
      assert_raises(ImageAttachments::Error) do
        ingest_image(batch: @batch, bytes: "junk", declared_content_type: nil, client_key: "broken")
      end

      error = assert_raises(ImageAttachments::Error) { claim { build_annotation } }

      assert_equal "attachments_not_ready", error.code
    end

    test "refuses a batch owned by another user" do
      ingest_image(batch: @batch)

      error = assert_raises(ImageAttachments::Error) do
        ImageAttachments::ClaimBatch.call(batch: @batch, user: users(:bob), project: @project) { build_annotation }
      end

      assert_equal "batch_not_owned", error.code
    end

    test "refuses an expired batch" do
      ingest_image(batch: @batch)
      @batch.update_columns(last_activity_at: 25.hours.ago, expires_at: 1.minute.ago)

      error = assert_raises(ImageAttachments::Error) { claim { build_annotation } }

      assert_equal "batch_unusable", error.code
    end

    test "an invalid message rolls the claim back and preserves the ready drafts" do
      attachment = ingest_image(batch: @batch)

      assert_raises(ActiveRecord::RecordInvalid) do
        claim { @screenshot.annotations.create!(user: @user, x_percent: 1, y_percent: 1, comment: "") }
      end

      assert_predicate @batch.reload, :state_open?
      assert_predicate attachment.reload, :draft?
      assert_predicate attachment, :state_ready?
    end

    test "claiming warms delivery variants only after the message exists" do
      ingest_image(batch: @batch)

      assert_enqueued_jobs 1, only: ImageAttachmentThumbnailJob do
        claim { build_annotation }
      end
    end

    test "a nil batch still builds the message and claims nothing" do
      result = ImageAttachments::ClaimBatch.call(batch: nil, user: @user, project: @project) { build_annotation }

      assert_empty result.attachments
      assert_not result.replayed?
      assert_predicate result.parent, :persisted?
    end

    test "an unsupported parent type is rejected" do
      ingest_image(batch: @batch)

      assert_raises(ArgumentError) { claim { @screenshot } }
    end

    private

    def claim(&block)
      ImageAttachments::ClaimBatch.call(batch: @batch, user: @user, project: @project, &block)
    end

    def build_annotation
      @screenshot.annotations.create!(
        user: @user, x_percent: 10, y_percent: 10, comment: "Look here", viewport: :desktop
      )
    end
  end
end
