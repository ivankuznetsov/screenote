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

  # A key allowlist proves that nothing was renamed; it proves nothing about
  # the values a shipped agent already reads. This compares the whole response
  # — every key, every literal value, and the exact nesting — against a
  # recorded golden. Only genuinely per-read values are replaced with named
  # placeholders, and each of those is asserted for shape on its own.
  test "the whole get_annotation payload matches the recorded golden" do
    scenario = golden_scenario
    payload = call_tool

    golden = JSON.parse(file_fixture("mcp_get_annotation_golden.json").read).except("_comment")

    assert_equal golden, normalize_golden(payload, scenario)

    assert_match(/\AiVBORw0KGgo/, payload.fetch("cropped_image_base64"))
    (payload.fetch("attachments") + payload.fetch("comments").flat_map { |c| c.fetch("attachments") }).each do |item|
      assert_match %r{\Ahttps?://[^?]+/api/media/image_attachments/\d+\?token=.+\z}, item.fetch("url")
      assert_in_delta ImageAttachment::MEDIA_TOKEN_EXPIRY.from_now,
        Time.zone.parse(item.fetch("url_expires_at")), 5
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

  # One annotation carrying every part of the envelope at once: a real cropped
  # region, a root image with author alt text, and two comments — an ordinary
  # reply that also carries an image, and a resolution that carries none.
  def golden_scenario
    attach_screenshot_image
    root = attach_to(@annotation, alt_text: "The disabled save button")
    reply = @annotation.annotation_comments.create!(user: @user, body: "And here", action: :comment)
    reply_attachment = attach_to(reply)
    resolution = @annotation.annotation_comments.create!(user: @user, body: "Fixed", action: :resolved)

    {
      "<annotation_id>" => @annotation.id,
      "<screenshot_id>" => @annotation.screenshot_id,
      "<reply_comment_id>" => reply.id,
      "<resolution_comment_id>" => resolution.id,
      "<root_attachment_id>" => root.id,
      "<reply_attachment_id>" => reply_attachment.id
    }
  end

  def attach_screenshot_image
    image = @annotation.screenshot.image_for(@annotation.viewport)
    image.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/desktop_screenshot.png")),
      filename: "screenshot.png",
      content_type: "image/png"
    )
    image.update!(status: :ready, width: 1440, height: 900)
  end

  # Replaces exactly what cannot be recorded: primary keys, wall-clock stamps,
  # the freshly encoded crop, and the media URL minted for this read. Everything
  # else has to match the golden byte for byte.
  #
  # Substitution is keyed on the field, never on the value. Keying on the value
  # would rewrite any number that happened to equal a row ID — `comments_count`,
  # a width, a byte size — and quietly stop asserting it.
  IDENTIFIER_KEYS = %w[id screenshot_id annotation_id].freeze

  def normalize_golden(value, scenario)
    identifiers = scenario.to_h { |placeholder, id| [ id, placeholder ] }

    case value
    when Hash
      value.to_h do |key, nested|
        case key
        when "created_at" then [ key, "<timestamp>" ]
        when "cropped_image_base64" then [ key, "<cropped-png-base64>" ]
        when "url" then [ key, "<media-url>" ]
        when "url_expires_at" then [ key, "<url-expiry>" ]
        when *IDENTIFIER_KEYS then [ key, identifiers.fetch(nested, nested) ]
        else [ key, normalize_golden(nested, scenario) ]
        end
      end
    when Array then value.map { |item| normalize_golden(item, scenario) }
    else value
    end
  end

  def call_tool
    JSON.parse(GetAnnotationTool.new.call(project_id: @project.id, annotation_id: @annotation.id))
  end

  def attach_to(parent, alt_text: nil)
    batch = build_batch(user: @user, project: @project)
    attachment = ingest_image(batch: batch)
    attachment.update!(alt_text: alt_text) if alt_text
    ImageAttachments::ClaimBatch.call(batch: batch, user: @user, project: @project, parent_type: parent.class) { parent }
    attachment.reload
  end
end
