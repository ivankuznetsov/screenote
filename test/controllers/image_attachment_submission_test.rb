# frozen_string_literal: true

require "test_helper"

class ImageAttachmentSubmissionTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    require_vips!
    @user = users(:alice)
    @project = projects(:alice_project)
    @screenshot = screenshots(:alice_screenshot)
    @annotation = annotations(:point_annotation)
    @batch = build_batch(user: @user, project: @project)
    sign_in @user
  end

  test "posting a root annotation binds every ready attachment" do
    first = ingest_image(batch: @batch, client_key: "a")
    second = ingest_image(batch: @batch, client_key: "b")

    post_annotation

    assert_response :created
    annotation = Annotation.find(response.parsed_body["annotation_id"])
    assert_equal [ first.id, second.id ], annotation.image_attachments.pluck(:id)
    assert_predicate @batch.reload, :state_claimed?
  end

  test "posting a reply binds attachments to the comment" do
    attachment = ingest_image(batch: @batch)

    post screenshot_annotation_annotation_comments_path(@screenshot, @annotation),
      params: { annotation_comment: { body: "See the crop" }, image_attachment_batch_id: @batch.public_id },
      as: :json

    assert_response :created
    comment = @annotation.annotation_comments.order(:id).last
    assert_equal [ attachment.id ], comment.image_attachments.pluck(:id)
  end

  test "reopening binds attachments to the reopen comment" do
    resolved = annotations(:resolved_annotation)
    attachment = ingest_image(batch: @batch)

    post screenshot_annotation_annotation_comments_path(@screenshot, resolved),
      params: {
        annotation_comment: { body: "Still broken", reopen: "1" },
        image_attachment_batch_id: @batch.public_id
      },
      as: :json

    assert_response :created
    comment = resolved.annotation_comments.where(action: :reopened).sole
    assert_equal [ attachment.id ], comment.image_attachments.pluck(:id)
    assert_predicate resolved.reload, :open?
  end

  test "a response-loss retry with the same batch returns the same message" do
    ingest_image(batch: @batch)
    post_annotation
    first_id = response.parsed_body["annotation_id"]

    assert_no_difference -> { Annotation.count } do
      post_annotation
    end

    assert_response :created
    assert_equal first_id, response.parsed_body["annotation_id"]
  end

  test "invalid text answers 422 with the batch and ready IDs for rehydration" do
    attachment = ingest_image(batch: @batch)

    post_annotation(comment: "")

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal @batch.public_id, body.dig("form", "image_attachment_batch_id")
    assert_equal [ attachment.id ], body.dig("form", "ready_attachment_ids")
    assert_predicate @batch.reload, :state_open?
    assert_predicate attachment.reload, :draft?
  end

  test "an overlong reply body answers 422 and preserves the draft" do
    attachment = ingest_image(batch: @batch)

    post screenshot_annotation_annotation_comments_path(@screenshot, @annotation),
      params: {
        annotation_comment: { body: "x" * 5001 },
        image_attachment_batch_id: @batch.public_id
      },
      as: :json

    assert_response :unprocessable_entity
    assert_equal [ attachment.id ], response.parsed_body.dig("form", "ready_attachment_ids")
    assert_predicate attachment.reload, :draft?
  end

  test "reopening an open annotation answers 422 and keeps the composer state" do
    ingest_image(batch: @batch)

    post screenshot_annotation_annotation_comments_path(@screenshot, @annotation),
      params: {
        annotation_comment: { body: "Reopen please", reopen: "1" },
        image_attachment_batch_id: @batch.public_id
      },
      as: :json

    assert_response :unprocessable_entity
    assert_equal "annotation_not_resolved", response.parsed_body.dig("error", "code")
    assert_equal @batch.public_id, response.parsed_body.dig("form", "image_attachment_batch_id")
  end

  test "a pending attachment blocks the post" do
    ingest_image(batch: @batch, client_key: "ready")
    @batch.image_attachments.create!(user: @user, project: @project, client_key: "pending")

    post_annotation

    assert_response :unprocessable_entity
    assert_equal "attachments_not_ready", response.parsed_body.dig("error", "code")
    assert_equal 0, Annotation.where(comment: "Look here").count
  end

  test "a failed attachment blocks the post" do
    ingest_image(batch: @batch, client_key: "ready")
    @batch.image_attachments.create!(
      user: @user, project: @project, client_key: "broken", state: :failed, failure_code: "invalid_image"
    )

    post_annotation

    assert_response :unprocessable_entity
    assert_equal "attachments_not_ready", response.parsed_body.dig("error", "code")
  end

  test "a batch belonging to another user is rejected" do
    foreign = build_batch(user: users(:bob), project: projects(:bob_project))

    post_annotation(batch_id: foreign.public_id)

    assert_response :unprocessable_entity
    assert_equal "batch_not_owned", response.parsed_body.dig("error", "code")
  end

  test "an unknown batch is rejected" do
    post_annotation(batch_id: "not-a-real-batch")

    assert_response :unprocessable_entity
    assert_equal "batch_not_owned", response.parsed_body.dig("error", "code")
  end

  test "an expired batch is rejected" do
    ingest_image(batch: @batch)
    @batch.update_columns(last_activity_at: 25.hours.ago, expires_at: 1.minute.ago)

    post_annotation

    assert_response :unprocessable_entity
    assert_equal "batch_unusable", response.parsed_body.dig("error", "code")
  end

  test "client supplied attachment fields are ignored" do
    attachment = ingest_image(batch: @batch)

    post screenshot_annotations_path(@screenshot),
      params: {
        annotation: {
          x_percent: 10, y_percent: 10, comment: "Look here", viewport: "desktop"
        },
        image_attachment_batch_id: @batch.public_id,
        image_attachment_ids: [ 999_999 ],
        image_attachments: [ { user_id: users(:bob).id, byte_size: 1, state: "ready" } ]
      },
      as: :json

    assert_response :created
    annotation = Annotation.find(response.parsed_body["annotation_id"])
    assert_equal [ attachment.id ], annotation.image_attachments.pluck(:id)
    assert_equal @user.id, attachment.reload.user_id
  end

  test "posting without a batch still works" do
    post screenshot_annotations_path(@screenshot),
      params: { annotation: { x_percent: 10, y_percent: 10, comment: "Look here" } }, as: :json

    assert_response :created
    assert_empty Annotation.find(response.parsed_body["annotation_id"]).image_attachments
  end

  # A rejected post always answers with composer state, even when the person
  # attached nothing: the still-mounted composer reads the same shape either
  # way instead of branching on whether a draft exists.
  test "a rejected post without a draft still answers with empty composer state" do
    post screenshot_annotations_path(@screenshot),
      params: { annotation: { x_percent: 10, y_percent: 10, comment: "Look here", viewport: "mobile" } },
      as: :json

    assert_response :unprocessable_entity
    assert_equal "invalid_viewport", response.parsed_body.dig("error", "code")
    assert_nil response.parsed_body.dig("form", "image_attachment_batch_id")
    assert_empty response.parsed_body.dig("form", "ready_attachment_ids")
  end

  # The non-JavaScript fallback has no composer to restore, so an attachment
  # failure has to land back on the workspace with the reason instead of
  # rendering a JSON body the browser would download.
  test "the HTML fallback returns an attachment failure to the workspace" do
    foreign = build_batch(user: users(:bob), project: projects(:bob_project))

    post screenshot_annotations_path(@screenshot),
      params: {
        annotation: { x_percent: 10, y_percent: 10, comment: "Look here" },
        image_attachment_batch_id: foreign.public_id
      }

    assert_redirected_to page_path(@screenshot.page_id, version_id: @screenshot.id)
    assert_equal 0, Annotation.where(comment: "Look here").count
  end

  test "the HTML reply fallback returns an attachment failure to the annotation" do
    foreign = build_batch(user: users(:bob), project: projects(:bob_project))

    post screenshot_annotation_annotation_comments_path(@screenshot, @annotation),
      params: {
        annotation_comment: { body: "See the crop" },
        image_attachment_batch_id: foreign.public_id
      }

    assert_redirected_to page_path(
      @screenshot.page_id, version_id: @screenshot.id, viewport: @annotation.viewport
    )
    assert_equal 0, @annotation.annotation_comments.where(body: "See the crop").count
  end

  test "the HTML fallback keeps redirecting" do
    post screenshot_annotations_path(@screenshot),
      params: { annotation: { x_percent: 10, y_percent: 10, comment: "Look here" } }

    assert_response :redirect
  end

  # A batch belongs to exactly one composer. Replaying its public ID against
  # the other endpoint is an ordinary rejection, not a parent of the wrong
  # class handed to a responder that cannot describe it.
  test "a reply batch replayed against the annotation endpoint is refused" do
    ingest_image(batch: @batch)
    post screenshot_annotation_annotation_comments_path(@screenshot, @annotation),
      params: { annotation_comment: { body: "See the crop" }, image_attachment_batch_id: @batch.public_id },
      as: :json
    assert_response :created

    assert_no_difference -> { Annotation.count } do
      post_annotation
    end

    assert_response :unprocessable_entity
    assert_equal "batch_not_owned", response.parsed_body.dig("error", "code")
  end

  test "a root batch replayed against the reply endpoint is refused" do
    ingest_image(batch: @batch)
    post_annotation
    assert_response :created

    assert_no_difference -> { AnnotationComment.count } do
      post screenshot_annotation_annotation_comments_path(@screenshot, @annotation),
        params: { annotation_comment: { body: "See the crop" }, image_attachment_batch_id: @batch.public_id },
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "batch_not_owned", response.parsed_body.dig("error", "code")
  end

  # A reply batch is claimed by one disclosure. Parent class alone cannot tell
  # two reply composers apart, so a public ID replayed from another thread must
  # not answer with that thread's comment as if this post had succeeded.
  test "a reply batch replayed from another thread is refused" do
    ingest_image(batch: @batch)
    post screenshot_annotation_annotation_comments_path(@screenshot, @annotation),
      params: { annotation_comment: { body: "See the crop" }, image_attachment_batch_id: @batch.public_id },
      as: :json
    assert_response :created

    other = annotations(:resolved_annotation)
    assert_no_difference -> { AnnotationComment.count } do
      post screenshot_annotation_annotation_comments_path(@screenshot, other),
        params: { annotation_comment: { body: "See the crop" }, image_attachment_batch_id: @batch.public_id },
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "batch_not_owned", response.parsed_body.dig("error", "code")
  end

  test "a reply batch replayed from the reopen composer is refused" do
    resolved = annotations(:resolved_annotation)
    ingest_image(batch: @batch)
    post screenshot_annotation_annotation_comments_path(@screenshot, resolved),
      params: { annotation_comment: { body: "See the crop" }, image_attachment_batch_id: @batch.public_id },
      as: :json
    assert_response :created

    assert_no_difference -> { AnnotationComment.count } do
      post screenshot_annotation_annotation_comments_path(@screenshot, resolved),
        params: {
          annotation_comment: { body: "See the crop", reopen: "1" },
          image_attachment_batch_id: @batch.public_id
        },
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "batch_not_owned", response.parsed_body.dig("error", "code")
  end

  # The first reopen leaves the annotation open, so a retry of the identical
  # request arrives against a state its own first attempt produced. It has to
  # reach the claimed batch and get the comment back.
  test "a response-loss retry of a reopen replays the comment it already created" do
    resolved = annotations(:resolved_annotation)
    ingest_image(batch: @batch)

    post_reopen(resolved)
    assert_response :created
    comment_id = response.parsed_body["annotation_comment_id"]
    assert_equal resolved.annotation_comments.where(action: :reopened).sole.id, comment_id

    assert_no_difference -> { AnnotationComment.count } do
      post_reopen(resolved)
    end

    assert_response :created
    assert_equal comment_id, response.parsed_body["annotation_comment_id"]
  end

  test "a reply response identifies the comment the claim produced" do
    ingest_image(batch: @batch)

    post screenshot_annotation_annotation_comments_path(@screenshot, @annotation),
      params: { annotation_comment: { body: "See the crop" }, image_attachment_batch_id: @batch.public_id },
      as: :json

    assert_response :created
    assert_equal @annotation.annotation_comments.order(:id).last.id,
      response.parsed_body["annotation_comment_id"]
  end

  test "an invalid root post returns the body and the selected region" do
    ingest_image(batch: @batch)

    post screenshot_annotations_path(@screenshot),
      params: {
        annotation: {
          x_percent: 12.5, y_percent: 30.25, width_percent: 8.0, height_percent: 4.5,
          comment: "", viewport: "desktop"
        },
        image_attachment_batch_id: @batch.public_id
      },
      as: :json

    assert_response :unprocessable_entity
    form = response.parsed_body.fetch("form")
    assert_equal "", form.fetch("body")
    assert_equal 12.5, form.fetch("x_percent")
    assert_equal 30.25, form.fetch("y_percent")
    assert_equal 8.0, form.fetch("width_percent")
    assert_equal 4.5, form.fetch("height_percent")
    assert_equal "desktop", form.fetch("viewport")
  end

  test "an invalid reply returns the body and the composer it came from" do
    ingest_image(batch: @batch)

    post screenshot_annotation_annotation_comments_path(@screenshot, @annotation),
      params: {
        annotation_comment: { body: "x" * 5001 },
        image_attachment_batch_id: @batch.public_id
      },
      as: :json

    assert_response :unprocessable_entity
    form = response.parsed_body.fetch("form")
    assert_equal "x" * 5001, form.fetch("body")
    assert_equal @annotation.id, form.fetch("annotation_id")
    assert_equal false, form.fetch("reopen")
  end

  test "an invalid reopen returns the body and its reopen intent" do
    ingest_image(batch: @batch)

    post screenshot_annotation_annotation_comments_path(@screenshot, @annotation),
      params: {
        annotation_comment: { body: "Reopen please", reopen: "1" },
        image_attachment_batch_id: @batch.public_id
      },
      as: :json

    assert_response :unprocessable_entity
    form = response.parsed_body.fetch("form")
    assert_equal "Reopen please", form.fetch("body")
    assert_equal true, form.fetch("reopen")
  end

  test "deleting the message removes its attachments and their bytes" do
    attachment = ingest_image(batch: @batch)
    post_annotation
    annotation = Annotation.find(response.parsed_body["annotation_id"])
    blob = attachment.reload.image.blob

    perform_enqueued_jobs { delete screenshot_annotation_path(@screenshot, annotation) }

    assert_not ImageAttachment.exists?(attachment.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not ImageAttachmentBatch.exists?(@batch.id)
  end

  private

  def post_annotation(comment: "Look here", batch_id: nil)
    post screenshot_annotations_path(@screenshot),
      params: {
        annotation: { x_percent: 10, y_percent: 10, comment: comment, viewport: "desktop" },
        image_attachment_batch_id: batch_id || @batch.public_id
      },
      as: :json
  end

  def post_reopen(annotation)
    post screenshot_annotation_annotation_comments_path(@screenshot, annotation),
      params: {
        annotation_comment: { body: "Still broken", reopen: "1" },
        image_attachment_batch_id: @batch.public_id
      },
      as: :json
  end
end
