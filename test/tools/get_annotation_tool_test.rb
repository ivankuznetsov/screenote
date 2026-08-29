# frozen_string_literal: true

require "test_helper"

class GetAnnotationToolTest < ActiveSupport::TestCase
  setup do
    require_vips!
    @user = users(:alice)
    @project = projects(:alice_project)
    @annotation = annotations(:point_annotation)
    Current.authenticated_principal = AuthenticatedPrincipal.for_user(@user)
  end

  teardown do
    Current.authenticated_principal = nil
  end

  test "the shipped response envelope is preserved and attachments are added" do
    golden = JSON.parse(file_fixture("mcp_get_annotation_keys.json").read)
    payload = call_tool

    golden.fetch("annotation").each do |key|
      assert payload.key?(key), "get_annotation dropped the shipped key #{key}"
    end
    assert_equal golden.fetch("coordinates").sort, payload.fetch("coordinates").keys.sort
    assert_includes payload.keys, "attachments"

    payload.fetch("comments").each do |comment|
      golden.fetch("comments").each do |key|
        assert comment.key?(key), "get_annotation dropped the shipped comment key #{key}"
      end
      assert comment.key?("attachments")
    end
  end

  test "attachments are an empty array when a message has none" do
    payload = call_tool

    assert_equal [], payload.fetch("attachments")
    assert(payload.fetch("comments").all? { |comment| comment.fetch("attachments") == [] })
  end

  test "root and comment attachments carry metadata and an expiring url" do
    attach_to(@annotation, alt_text: "The broken button")
    comment = @annotation.annotation_comments.create!(user: @user, body: "And here")
    attach_to(comment)

    payload = call_tool

    root = payload.fetch("attachments").sole
    assert_equal "The broken button", root.fetch("alt_text")
    assert_equal "image/png", root.fetch("media_type")
    assert_equal 8, root.fetch("width")
    assert_operator root.fetch("size"), :>, 0
    assert_match %r{/api/media/image_attachments/\d+\?token=}, root.fetch("url")
    assert_in_delta ImageAttachment::MEDIA_TOKEN_EXPIRY.from_now,
      Time.zone.parse(root.fetch("url_expires_at")), 5

    reply = payload.fetch("comments").find { |item| item["body"] == "And here" }
    assert_equal 1, reply.fetch("attachments").size
  end

  test "no storage key or semantic filename is exposed" do
    attachment = attach_to(@annotation)

    payload = call_tool.to_json

    assert_not payload.include?(attachment.image.blob.key)
    assert_not payload.include?("filename")
    assert_not payload.include?("service_name")
  end

  private

  def call_tool
    JSON.parse(GetAnnotationTool.new.call(project_id: @project.id, annotation_id: @annotation.id))
  end

  def attach_to(parent, alt_text: nil)
    batch = build_batch(user: @user, project: @project)
    attachment = ingest_image(batch: batch)
    attachment.update!(alt_text: alt_text) if alt_text
    ImageAttachments::ClaimBatch.call(batch: batch, user: @user, project: @project) { parent }
    attachment.reload
  end
end
