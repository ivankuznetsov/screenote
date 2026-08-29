# frozen_string_literal: true

require "test_helper"

module ImageAttachmentDrafts
  class AttachmentsControllerTest < ActionDispatch::IntegrationTest
    setup do
      require_vips!
      @user = users(:alice)
      @project = projects(:alice_project)
      @batch = build_batch(user: @user, project: @project)
      sign_in @user
    end

    test "uploads a file and returns stable metadata without provider details" do
      post_upload("shot.png")

      assert_response :created
      attachment = response.parsed_body["attachment"]
      assert_equal "ready", attachment["state"]
      assert_equal "image/png", attachment["media_type"]
      assert_equal 8, attachment["width"]
      assert_equal "one", attachment["client_key"]
      assert_match %r{\A/media/image_attachments/\d+/original\z}, attachment["preview_url"]
      assert_nil attachment["failure"]
      assert_not response.body.include?("service_name")
      assert_not response.body.include?(ActiveStorage::Blob.last.key)
    end

    test "reports an actionable machine code for an unreadable file" do
      post image_attachment_draft_batch_attachments_path(@batch.public_id),
        params: { client_key: "bad", file: uploaded("junk.png", "not an image") },
        headers: { "ACCEPT" => "application/json" }

      assert_response :unprocessable_entity
      error = response.parsed_body["error"]
      assert_equal "invalid_image", error["code"]
      assert_equal "Attachments must be PNG, JPEG, or WebP images.", error["message"]
      assert_predicate @batch.image_attachments.sole, :state_failed?
    end

    test "a failed row is still reported so the composer can retry or remove it" do
      post image_attachment_draft_batch_attachments_path(@batch.public_id),
        params: { client_key: "bad", file: uploaded("junk.png", "not an image") },
        headers: { "ACCEPT" => "application/json" }

      get image_attachment_draft_batch_path(@batch.public_id), as: :json

      attachment = response.parsed_body["attachments"].sole
      assert_equal "failed", attachment["state"]
      assert_equal "invalid_image", attachment.dig("failure", "code")
      assert attachment.dig("failure", "retryable")
      assert_nil attachment["preview_url"]
    end

    test "edits alt text on a draft" do
      post_upload("shot.png")
      id = response.parsed_body.dig("attachment", "id")

      patch image_attachment_draft_batch_attachment_path(@batch.public_id, id),
        params: { image_attachment: { alt_text: "The disabled save button" } }, as: :json

      assert_response :success
      assert_equal "The disabled save button", response.parsed_body.dig("attachment", "alt_text")
    end

    test "removal is idempotent" do
      post_upload("shot.png")
      id = response.parsed_body.dig("attachment", "id")

      2.times do
        delete image_attachment_draft_batch_attachment_path(@batch.public_id, id), as: :json

        assert_response :success
        assert_empty response.parsed_body["attachments"]
      end
      assert_equal 0, @batch.image_attachments.count
    end

    test "a collaborator cannot upload into another member's draft" do
      @project.project_memberships.find_or_create_by!(user: users(:bob)) { |m| m.role = :member }
      delete session_path
      sign_in users(:bob)

      post_upload("shot.png")

      assert_response :not_found
    end

    test "an expired batch refuses new uploads" do
      @batch.update_columns(last_activity_at: 25.hours.ago, expires_at: 1.minute.ago)

      post_upload("shot.png")

      assert_response :unprocessable_entity
      assert_equal "batch_unusable", response.parsed_body.dig("error", "code")
    end

    test "uploads require a CSRF token" do
      with_forgery_protection do
        post_upload("shot.png")

        assert_response :unprocessable_entity
      end
    end

    test "editing alt text requires a CSRF token" do
      post_upload("shot.png")
      id = response.parsed_body.dig("attachment", "id")

      with_forgery_protection do
        patch image_attachment_draft_batch_attachment_path(@batch.public_id, id),
          params: { image_attachment: { alt_text: "Injected" } }, as: :json

        assert_response :unprocessable_entity
      end
      assert_nil ImageAttachment.find(id).alt_text
    end

    test "an upload carrying the composer's token passes forgery protection" do
      with_forgery_protection do
        post image_attachment_draft_batch_attachments_path(@batch.public_id),
          params: { client_key: "one", file: uploaded("shot.png", image_bytes) },
          headers: { "ACCEPT" => "application/json", "X-CSRF-Token" => csrf_token }

        assert_response :created
        assert_equal "ready", response.parsed_body.dig("attachment", "state")
      end
    end

    test "the per-file ceiling measures the uploaded part, not the multipart envelope" do
      bytes = image_bytes

      stub_const(ImageAttachment, :MAX_FILE_SIZE, bytes.bytesize + 1) do
        post image_attachment_draft_batch_attachments_path(@batch.public_id),
          params: { client_key: "one", file: uploaded("a-rather-long-original-filename.png", bytes) },
          headers: { "ACCEPT" => "application/json" }

        assert_operator request.content_length, :>, ImageAttachment::MAX_FILE_SIZE
        assert_response :created
      end
    end

    test "removal requires a CSRF token" do
      post_upload("shot.png")
      id = response.parsed_body.dig("attachment", "id")

      with_forgery_protection do
        delete image_attachment_draft_batch_attachment_path(@batch.public_id, id), as: :json

        assert_response :unprocessable_entity
      end
    end

    private

    def post_upload(name, client_key: "one")
      post image_attachment_draft_batch_attachments_path(@batch.public_id),
        params: { client_key: client_key, file: uploaded(name, image_bytes) },
        headers: { "ACCEPT" => "application/json" }
    end

    def uploaded(name, bytes)
      Rack::Test::UploadedFile.new(StringIO.new(bytes), "image/png", original_filename: name)
    end

    # The composer reads the same meta tag every rendered page carries.
    def csrf_token
      get root_path
      follow_redirect! while response.redirect?
      css_select("meta[name='csrf-token']").first["content"]
    end
  end
end
