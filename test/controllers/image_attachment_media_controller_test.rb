# frozen_string_literal: true

require "test_helper"

class ImageAttachmentMediaControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    require_vips!
    @user = users(:alice)
    @project = projects(:alice_project)
    @batch = build_batch(user: @user, project: @project)
    sign_in @user
  end

  test "the uploader can preview their own draft" do
    attachment = ingest_image(batch: @batch)

    get image_attachment_media_path(attachment, :original)

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "bytes", response.headers["Accept-Ranges"]
    assert_nil response.headers["Location"]
  end

  test "a same-project collaborator cannot read a guessed draft ID" do
    attachment = ingest_image(batch: @batch)
    @project.project_memberships.find_or_create_by!(user: users(:bob)) { |m| m.role = :member }
    delete session_path
    sign_in users(:bob)

    get image_attachment_media_path(attachment, :original)

    assert_response :not_found
  end

  test "an expired draft is no longer readable" do
    attachment = ingest_image(batch: @batch)
    @batch.update_columns(last_activity_at: 25.hours.ago, expires_at: 1.minute.ago)

    get image_attachment_media_path(attachment, :original)

    assert_response :not_found
  end

  test "every project member can read a submitted attachment" do
    attachment = submitted_attachment
    @project.project_memberships.find_or_create_by!(user: users(:bob)) { |m| m.role = :member }
    delete session_path
    sign_in users(:bob)

    get image_attachment_media_path(attachment, :original)

    assert_response :success
  end

  test "revoking membership immediately revokes attachment reads" do
    attachment = submitted_attachment
    @project.project_memberships.find_or_create_by!(user: users(:bob)) { |m| m.role = :member }
    delete session_path
    sign_in users(:bob)
    get image_attachment_media_path(attachment, :original)
    assert_response :success

    @project.project_memberships.where(user: users(:bob)).delete_all

    get image_attachment_media_path(attachment, :original)
    assert_response :not_found
  end

  test "a GET never triggers image decoding" do
    attachment = submitted_attachment
    calls = 0
    original = ImageDecoding::Guard.method(:synchronize)
    ImageDecoding::Guard.define_singleton_method(:synchronize) do |**options, &operation|
      calls += 1
      original.call(**options, &operation)
    end

    get image_attachment_media_path(attachment, :attachment_thumb_1x)

    assert_response :not_found
    assert_equal 0, calls
  ensure
    ImageDecoding::Guard.define_singleton_method(:synchronize, original) if original
  end

  test "a warmed variant is delivered without decoding" do
    attachment = submitted_attachment
    perform_enqueued_jobs(only: ImageAttachmentThumbnailJob)

    get image_attachment_media_path(attachment, :attachment_thumb_1x)

    assert_response :success
  end

  test "the download variant uses an attachment disposition" do
    attachment = submitted_attachment

    get image_attachment_media_path(attachment, :download)

    assert_response :success
    assert_match(/\Aattachment;/, response.headers["Content-Disposition"])
  end

  test "unknown variants are not routable" do
    attachment = submitted_attachment

    get "/media/image_attachments/#{attachment.id}/page_card_1x"

    assert_response :not_found
  end

  test "a row that has not finished uploading has no bytes to serve" do
    pending = @batch.image_attachments.create!(user: @user, project: @project, client_key: "pending")

    get image_attachment_media_path(pending, :original)

    assert_response :not_found
  end

  # The draft rule is "the uploader, while the batch is still live". A row whose
  # batch is gone has no live batch to be read against, so it is unreadable
  # rather than readable by default.
  test "a draft whose batch row is gone is unreadable" do
    attachment = ingest_image(batch: @batch)
    ImageAttachment.connection.disable_referential_integrity do
      ImageAttachmentBatch.where(id: @batch.id).delete_all
    end

    get image_attachment_media_path(attachment, :original)

    assert_response :not_found
  end

  # The route constraint and the served variant list are declared separately,
  # so the controller refuses a name it does not own rather than handing it to
  # Active Storage.
  test "a variant outside the media contract is never resolved" do
    attachment = submitted_attachment

    assert_nil ImageAttachmentMediaController.new.send(:media_blob, attachment, "page_card_1x")
  end

  test "an unknown attachment ID is a private not-found" do
    get image_attachment_media_path(999_999, :original)

    assert_response :not_found
  end

  test "an attachment whose message was deleted is unreadable" do
    attachment = submitted_attachment
    ImageAttachment.connection.disable_referential_integrity do
      Annotation.where(id: attachment.annotation_id).delete_all
    end

    get image_attachment_media_path(attachment, :original)

    assert_response :not_found
  end

  private

  def submitted_attachment
    ingest_image(batch: @batch)
    ImageAttachments::ClaimBatch.call(batch: @batch, user: @user, project: @project) do
      screenshots(:alice_screenshot).annotations.create!(
        user: @user, x_percent: 1, y_percent: 1, comment: "Posted"
      )
    end.attachments.sole
  end
end
