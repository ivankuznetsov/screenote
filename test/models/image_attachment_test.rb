# frozen_string_literal: true

require "test_helper"

class ImageAttachmentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @batch = build_batch
  end

  test "a draft belongs to a batch and no message" do
    attachment = @batch.image_attachments.create!(
      user: users(:alice), project: projects(:alice_project), client_key: "a"
    )

    assert_predicate attachment, :draft?
    assert_not_predicate attachment, :submitted?
  end

  test "an attachment cannot belong to both a batch and a message" do
    attachment = ImageAttachment.new(
      image_attachment_batch: @batch,
      annotation: annotations(:point_annotation),
      user: users(:alice),
      project: projects(:alice_project),
      client_key: "a"
    )

    assert_not attachment.valid?
    assert_includes attachment.errors[:base], "must belong to exactly one draft batch or message"
  end

  test "an attachment cannot belong to two messages" do
    attachment = ImageAttachment.new(
      annotation: annotations(:point_annotation),
      annotation_comment: annotation_comments(:resolved_comment),
      user: users(:alice),
      project: projects(:alice_project),
      client_key: "a"
    )

    assert_not attachment.valid?
    assert_includes attachment.errors[:base], "must belong to exactly one draft batch or message"
  end

  test "a submitted attachment must be ready and fully measured" do
    attachment = ImageAttachment.new(
      annotation: annotations(:point_annotation),
      user: users(:alice),
      project: projects(:alice_project),
      client_key: "a",
      state: :uploading
    )

    assert_not attachment.valid?
    assert_includes attachment.errors[:state], "submitted attachment must be ready"
  end

  test "submitted metadata and alt text are immutable" do
    attachment = submitted_attachment

    attachment.alt_text = "changed"
    assert_not attachment.valid?
    assert_includes attachment.errors[:alt_text], "cannot change after submission"
  end

  test "uploader and project are immutable" do
    attachment = @batch.image_attachments.create!(
      user: users(:alice), project: projects(:alice_project), client_key: "a"
    )

    attachment.user = users(:bob)
    assert_not attachment.valid?
    assert_includes attachment.errors[:user_id], "cannot change"
  end

  test "alt text falls back to a neutral label" do
    attachment = @batch.image_attachments.create!(
      user: users(:alice), project: projects(:alice_project), client_key: "a"
    )

    assert_equal "Attached image", attachment.display_alt_text
    attachment.update!(alt_text: "  A red button  ")
    assert_equal "A red button", attachment.display_alt_text
  end

  test "database rejects a submitted row that is not ready" do
    assert_raises ActiveRecord::StatementInvalid do
      ImageAttachment.connection.execute(<<~SQL.squish)
        INSERT INTO image_attachments
          (annotation_id, user_id, project_id, state, client_key, created_at, updated_at)
        VALUES
          (#{annotations(:point_annotation).id}, #{users(:alice).id},
           #{projects(:alice_project).id}, 0, 'sql', '2026-01-01', '2026-01-01')
      SQL
    end
  end

  test "database rejects an attachment with two message parents" do
    assert_raises ActiveRecord::StatementInvalid do
      ImageAttachment.connection.execute(<<~SQL.squish)
        INSERT INTO image_attachments
          (annotation_id, annotation_comment_id, user_id, project_id, state, client_key,
           media_type, width, height, byte_size, created_at, updated_at)
        VALUES
          (#{annotations(:point_annotation).id}, #{annotation_comments(:resolved_comment).id},
           #{users(:alice).id}, #{projects(:alice_project).id}, 1, 'sql',
           'image/png', 1, 1, 1, '2026-01-01', '2026-01-01')
      SQL
    end
  end

  test "destroying a message destroys its attachments and purges the blob" do
    require_vips!
    annotation = annotations(:point_annotation)
    attachment = ingest_image(batch: @batch)
    ImageAttachments::ClaimBatch.call(batch: @batch, user: users(:alice), project: projects(:alice_project)) do
      annotation
    end
    blob = attachment.reload.image.blob

    assert_difference -> { ImageAttachment.count } => -1 do
      perform_enqueued_jobs { annotation.destroy! }
    end
    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test "deleting a user with attachments on another member's message is rejected" do
    require_vips!
    projects(:alice_project).project_memberships.find_or_create_by!(user: users(:bob)) { |m| m.role = :member }
    batch = build_batch(user: users(:bob))
    ingest_image(batch: batch)
    ImageAttachments::ClaimBatch.call(batch: batch, user: users(:bob), project: projects(:alice_project)) do
      annotations(:point_annotation).annotation_comments.create!(user: users(:bob), body: "See this")
    end

    assert_not users(:bob).destroy
    assert_includes users(:bob).errors[:base].join, "image attachment"
    assert User.exists?(users(:bob).id)
  end

  test "deleting a user removes their own drafts" do
    require_vips!
    batch = build_batch(user: users(:free_user), project: projects(:demo_project))
    projects(:demo_project).project_memberships.find_or_create_by!(user: users(:free_user)) { |m| m.role = :member }
    ingest_image(batch: batch)

    assert_difference -> { ImageAttachmentBatch.count } => -1, -> { ImageAttachment.count } => -1 do
      assert users(:free_user).destroy
    end
  end

  private

  def submitted_attachment
    ImageAttachment.create!(
      annotation: annotations(:point_annotation),
      user: users(:alice),
      project: projects(:alice_project),
      client_key: "submitted-#{SecureRandom.hex(4)}",
      state: :ready,
      media_type: "image/png",
      width: 8,
      height: 8,
      byte_size: 100
    )
  end
end
