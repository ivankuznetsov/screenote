# frozen_string_literal: true

require "test_helper"

class NotificationMailerAttachmentsTest < ActionMailer::TestCase
  setup do
    require_vips!
    @user = users(:alice)
    @project = projects(:alice_project)
    @annotation = annotations(:point_annotation)
  end

  test "the digest describes root and latest pre-resolution reply attachments" do
    attach_to(@annotation, alt_text: "The broken header")
    old_reply = create_reply("Older reply", at: 3.hours.ago)
    attach_to(old_reply, alt_text: "Stale evidence")
    latest_reply = create_reply("Latest reply", at: 2.hours.ago)
    attach_to(latest_reply, alt_text: "Current evidence")
    resolution = create_resolution(at: 1.hour.ago)

    body = deliver(resolution).body.to_s

    assert_includes body, "The broken header"
    assert_includes body, "Current evidence"
    assert_not_includes body, "Stale evidence"
  end

  test "a reply posted after the resolution is not described" do
    latest_reply = create_reply("Before", at: 2.hours.ago)
    attach_to(latest_reply, alt_text: "Before evidence")
    resolution = create_resolution(at: 1.hour.ago)
    later = create_reply("After", at: 30.minutes.ago)
    attach_to(later, alt_text: "After evidence")

    body = deliver(resolution).body.to_s

    assert_includes body, "Before evidence"
    assert_not_includes body, "After evidence"
  end

  test "the call to action deep links to the annotation and embeds no blob url" do
    attachment = attach_to(@annotation)
    resolution = create_resolution(at: 1.hour.ago)

    body = deliver(resolution).body.to_s

    assert_includes body, "/pages/#{@annotation.screenshot.page_id}"
    assert_includes body, "version_id=#{@annotation.screenshot_id}"
    assert_includes body, "#annotation_#{@annotation.id}"
    assert_not_includes body, attachment.image.blob.key
    assert_not_includes body, "/media/image_attachments/"
    assert_not_includes body, "/api/media/image_attachments/"
  end

  test "a message without attachments describes none" do
    resolution = create_resolution(at: 1.hour.ago)

    body = deliver(resolution).body.to_s

    assert_not_includes body, "images attached"
  end

  private

  def deliver(resolution)
    NotificationMailer.resolution_digest(@user, [ resolution ])
  end

  def create_reply(text, at:)
    @annotation.annotation_comments.create!(user: users(:bob), body: text, action: :comment).tap do |comment|
      comment.update_columns(created_at: at)
    end
  end

  def create_resolution(at:)
    @annotation.update!(status: :resolved, resolved_by_user: users(:bob))
    @annotation.annotation_comments.create!(user: users(:bob), body: "Fixed", action: :resolved).tap do |comment|
      comment.update_columns(created_at: at)
    end
  end

  def attach_to(parent, alt_text: nil)
    batch = build_batch(user: @user, project: @project)
    attachment = ingest_image(batch: batch)
    attachment.update!(alt_text: alt_text) if alt_text
    ImageAttachments::ClaimBatch.call(batch: batch, user: @user, project: @project) { parent }
    attachment.reload
  end
end
