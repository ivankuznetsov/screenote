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
      raised = response.parsed_body.dig("error", "retryable")

      get image_attachment_draft_batch_path(@batch.public_id), as: :json

      attachment = response.parsed_body["attachments"].sole
      assert_equal "failed", attachment["state"]
      assert_equal "invalid_image", attachment.dig("failure", "code")
      # Bytes the decoder will never accept are removable, not retryable, and a
      # resumed row has to say exactly what the raise already said.
      assert_equal raised, attachment.dig("failure", "retryable")
      assert_not attachment.dig("failure", "retryable")
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
      assert_predicate @batch.image_attachments.sole, :removal_tombstone?
      assert_not @batch.image_attachments.sole.image.attached?
    end

    test "removal by client key wins before an upload reserves its row" do
      delete discard_image_attachment_draft_batch_attachments_path(@batch.public_id),
        params: { client_key: "not-reserved-yet" }, as: :json

      assert_response :success
      assert_empty response.parsed_body["attachments"]
      assert_predicate @batch.image_attachments.sole, :removal_tombstone?

      post_upload("shot.png", client_key: "not-reserved-yet")

      assert_response :not_found
      assert_equal "attachment_removed", response.parsed_body.dig("error", "code")
      assert_predicate @batch.image_attachments.sole, :removal_tombstone?
      assert_not @batch.image_attachments.sole.image.attached?
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

    test "client-key removal requires a CSRF token" do
      with_forgery_protection do
        delete discard_image_attachment_draft_batch_attachments_path(@batch.public_id),
          params: { client_key: "protected" }, as: :json

        assert_response :unprocessable_entity
      end
      assert_empty @batch.image_attachments
    end

    test "an upload with no file is an actionable client error" do
      post image_attachment_draft_batch_attachments_path(@batch.public_id),
        params: { client_key: "one" }, headers: { "ACCEPT" => "application/json" }

      assert_response :unprocessable_entity
      assert_equal "missing_file", response.parsed_body.dig("error", "code")
      assert_empty @batch.image_attachments
    end

    # Guessed draft IDs must not tell an attacker which ones exist, so an
    # unknown draft answers exactly like somebody else's.
    test "an unknown draft is a private not-found" do
      post image_attachment_draft_batch_attachments_path("not-a-real-batch"),
        params: { client_key: "one", file: uploaded("shot.png", image_bytes) },
        headers: { "ACCEPT" => "application/json" }

      assert_response :not_found
      assert_equal "not_found", response.parsed_body.dig("error", "code")
    end

    test "an exhausted per-user upload budget is refused before any bytes are read" do
      with_rate_limit_backend(SaturatedRateLimitBackend.new(matching: "user:")) do
        post_upload("shot.png")
      end

      assert_response :too_many_requests
      assert_equal "rate_limited", response.parsed_body.dig("error", "code")
      assert_empty @batch.image_attachments
    end

    # The address bucket is independent of the account bucket: one host cannot
    # spend everybody else's budget by signing in as somebody new.
    test "an exhausted per-address upload budget is refused on its own" do
      with_rate_limit_backend(SaturatedRateLimitBackend.new(matching: "ip:")) do
        post_upload("shot.png")
      end

      assert_response :too_many_requests
      assert_equal "rate_limited", response.parsed_body.dig("error", "code")
      assert_empty @batch.image_attachments
    end

    test "an unavailable limiter backend fails closed instead of admitting the upload" do
      with_rate_limit_backend(UnavailableRateLimitBackend.new) do
        post_upload("shot.png")
      end

      assert_response :service_unavailable
      body = response.parsed_body
      assert_equal "rate_limiter_unavailable", body.dig("error", "code")
      assert body.dig("error", "retryable")
      assert_empty @batch.image_attachments
    end

    private

    # Rails builds one cache key per limiter, so a double that saturates only
    # the identity it is asked about proves each bucket is enforced separately.
    class SaturatedRateLimitBackend
      def initialize(matching:)
        @matching = matching
      end

      def increment(key, _amount = 1, **)
        key.to_s.include?(@matching) ? BaseController::RATE_LIMIT + 1 : 1
      end
    end

    class UnavailableRateLimitBackend
      def increment(*, **)
        raise IOError, "backend unavailable"
      end
    end

    def with_rate_limit_backend(backend)
      original = BaseController.cache_store
      BaseController.cache_store = backend
      yield
    ensure
      BaseController.cache_store = original
    end

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
