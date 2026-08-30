# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ImageCommentsControllerTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"
      CAPABILITY = "image-comments-v1"

      setup do
        require_vips!
        @controller_class = Api::V1::ImageCommentsController
        @original_rate_limit_backend = @controller_class.cache_store
        @controller_class.cache_store = ActiveSupport::Cache::MemoryStore.new
        @annotation = annotations(:point_annotation)
        @project = projects(:alice_project)
        @bytes = image_bytes
        @key = "controller_image_comment_key_1234"
      end

      teardown do
        @controller_class.cache_store = @original_rate_limit_backend
      end

      test "api key creates one image comment with stable URL-free metadata" do
        assert_difference [ "AnnotationComment.count", "ImageAttachment.count", "ActiveStorage::Blob.count" ], 1 do
          post_image
        end

        assert_response :created
        assert_capability
        payload = response.parsed_body
        assert_equal "created", payload.fetch("operation")
        assert_equal "Use this layout", payload.dig("comment", "body")
        assert_equal "Alice's CI Key", payload.dig("comment", "author")
        assert_equal %w[alt_text height id media_type size width], payload.fetch("attachment").keys.sort
        assert_equal "image/png", payload.dig("attachment", "media_type")
        assert_not_includes response.body, "url"
        assert_not_includes response.body, "token"
      end

      test "identical request replay returns the same IDs with success status" do
        post_image
        first = response.parsed_body

        assert_no_difference [ "AnnotationComment.count", "ImageAttachment.count", "ActiveStorage::Blob.count" ] do
          post_image
        end

        assert_response :ok
        assert_capability
        assert_equal "replayed", response.parsed_body.fetch("operation")
        assert_equal first.dig("comment", "id"), response.parsed_body.dig("comment", "id")
        assert_equal first.dig("attachment", "id"), response.parsed_body.dig("attachment", "id")
      end

      test "same key with changed content returns a stable conflict without another pair" do
        post_image

        assert_no_difference [ "AnnotationComment.count", "ImageAttachment.count", "ActiveStorage::Blob.count" ] do
          post_image(body: "Use a different layout")
        end

        assert_response :conflict
        assert_equal "idempotency_conflict", response.parsed_body.fetch("code")
        assert_capability
      end

      test "oauth user and project-bound tokens create user-authored image comments" do
        user_token = oauth_token(user: users(:alice), scopes: "mcp_write")
        post_image(token: user_token.token, key: "oauth_user_image_key_123456")
        assert_response :created
        assert_equal users(:alice), AnnotationComment.last.user

        project_token = create_oauth_token(
          application: create_oauth_application(name: "Project CLI"),
          user: users(:alice),
          project: @project,
          scopes: "mcp_write"
        )
        post_image(token: project_token.token, key: "oauth_project_image_key_123")
        assert_response :created
        assert_equal users(:alice), AnnotationComment.last.user
      end

      test "accepts PNG JPEG and WebP through the multipart contract" do
        { "png" => "image/png", "jpg" => "image/jpeg", "webp" => "image/webp" }.each do |format, media_type|
          bytes = image_bytes(format: format)
          post_image(
            bytes:,
            media_type:,
            filename: "upload.#{format}",
            key: "allowed_#{format}_image_key_123456"
          )

          assert_response :created
          assert_equal media_type, response.parsed_body.dig("attachment", "media_type")
        end
      end

      test "requires exactly one images array part and a scalar body" do
        post_image(include_image: false, key: "missing_image_key_123456789")
        assert_response :unprocessable_entity
        assert_equal "missing_image", response.parsed_body.fetch("code")

        post_image(image_count: 2, key: "two_images_key_1234567890")
        assert_response :unprocessable_entity
        assert_equal "too_many_images", response.parsed_body.fetch("code")

        post_image(use_scalar_image_name: true, key: "scalar_image_key_123456789")
        assert_response :unprocessable_entity
        assert_equal "missing_image", response.parsed_body.fetch("code")

        post_image(body: "", key: "empty_body_image_key_123456")
        assert_response :unprocessable_entity
        assert_equal "invalid_body", response.parsed_body.fetch("code")
      end

      test "rejects missing malformed and conflicting request identity" do
        post_image(key: nil)
        assert_response :unprocessable_entity
        assert_equal "invalid_idempotency_key", response.parsed_body.fetch("code")
        assert_capability

        post_image(key: "bad key")
        assert_response :unprocessable_entity
        assert_equal "invalid_idempotency_key", response.parsed_body.fetch("code")

        post_image(digest: "0" * 64, key: "wrong_digest_image_key_1234")
        assert_response :conflict
        assert_equal "content_digest_mismatch", response.parsed_body.fetch("code")

        post_image(digest: "not-a-sha256", key: "malformed_digest_image_key_123")
        assert_response :conflict
        assert_equal "content_digest_mismatch", response.parsed_body.fetch("code")
      end

      test "new-server annotation not found remains distinguishable from a missing route" do
        post_image(annotation: annotations(:bob_annotation), key: "missing_annotation_key_1234")

        assert_response :not_found
        assert_equal "annotation_not_found", response.parsed_body.fetch("code")
        assert_capability
      end

      test "scope project and authentication failures create no text-only comment" do
        read_token = oauth_token(user: users(:alice), scopes: "mcp_read")

        assert_no_difference [ "AnnotationComment.count", "ImageAttachment.count" ] do
          post_image(token: read_token.token, key: "read_scope_image_key_123456")
          assert_response :forbidden
          assert_equal "insufficient_scope", response.parsed_body.fetch("code")
          assert_capability

          post_image(project: projects(:bob_project), key: "wrong_project_image_key_1234")
          assert_response :forbidden
          assert_equal "forbidden", response.parsed_body.fetch("code")
          assert_capability

          post_image(token: nil, key: "anonymous_image_key_1234567")
          assert_response :unauthorized
          assert_nil response.headers["Screenote-API-Capability"]
        end
      end

      test "rate limiting happens before malformed multipart parsing" do
        with_rate_limit_backend(SaturatedRateLimitBackend.new) do
          post raw_image_comments_path,
            headers: auth_headers(ALICE_TOKEN).merge(
              "Content-Type" => "multipart/form-data; boundary=broken",
              "Idempotency-Key" => @key
            ),
            env: { "RAW_POST_DATA" => "not multipart" }
        end

        assert_response :too_many_requests
        assert_equal "rate_limited", response.parsed_body.fetch("code")
        assert_equal 1.hour.to_i.to_s, response.headers.fetch("Retry-After")
        assert_capability
      end

      test "authentication happens before malformed multipart parsing" do
        post raw_image_comments_path,
          headers: {
            "Content-Type" => "multipart/form-data; boundary=broken",
            "Idempotency-Key" => @key
          },
          env: { "RAW_POST_DATA" => "not multipart" }

        assert_response :unauthorized
        assert_equal "unauthorized", response.parsed_body.fetch("code")
        assert_nil response.headers["Screenote-API-Capability"]
      end

      test "declared oversized requests are rejected by the route boundary" do
        post raw_image_comments_path,
          headers: auth_headers(ALICE_TOKEN).merge(
            "Content-Type" => "multipart/form-data; boundary=unused",
            "Content-Length" => (Screenote::ImageCommentRequestLimit.max_request_size + 1).to_s,
            "Idempotency-Key" => @key
          ),
          env: { "RAW_POST_DATA" => "ignored" }

        assert_response 413
        assert_equal "request_too_large", response.parsed_body.fetch("code")
        assert_nil response.headers["Screenote-API-Capability"]
      end

      test "declared oversized route aliases are rejected before controller dispatch" do
        paths = [
          "#{raw_image_comments_path}/",
          "#{raw_image_comments_path}//",
          "#{raw_image_comments_path}.json/"
        ]

        paths.each do |path|
          post path,
            headers: auth_headers(ALICE_TOKEN).merge(
              "Content-Type" => "multipart/form-data; boundary=unused",
              "Content-Length" => (Screenote::ImageCommentRequestLimit.max_request_size + 1).to_s,
              "Idempotency-Key" => @key
            ),
            env: { "RAW_POST_DATA" => "ignored" }

          assert_response 413, path
          assert_equal "request_too_large", response.parsed_body.fetch("code"), path
          assert_nil response.headers["Screenote-API-Capability"], path
        end
      end

      test "rate limiting fails closed before multipart parsing when its store is unavailable" do
        with_rate_limit_backend(UnavailableRateLimitBackend.new) do
          post_image
        end

        assert_response :service_unavailable
        assert_equal "rate_limit_unavailable", response.parsed_body.fetch("code")
        assert_equal "60", response.headers.fetch("Retry-After")
        assert_equal "no-store", response.headers.fetch("Cache-Control")
        assert_capability
      end

      test "provider failures return a generic stable error without leaking storage details" do
        original = ImageAttachments::PrepareUpload::Result.instance_method(:stage!)
        ImageAttachments::PrepareUpload::Result.define_method(:stage!) do |**|
          raise IOError, "s3 secret-bucket object-key"
        end

        assert_no_difference [ "AnnotationComment.count", "ImageAttachment.count", "ActiveStorage::Blob.count" ] do
          post_image
        end

        assert_response :internal_server_error
        assert_equal "upload_failed", response.parsed_body.fetch("code")
        assert_not_includes response.body, "secret-bucket"
        assert_capability
      ensure
        ImageAttachments::PrepareUpload::Result.define_method(:stage!, original) if original
      end

      private

      class SaturatedRateLimitBackend
        def increment(*)
          Api::V1::ImageCommentsController::UPLOAD_RATE_LIMIT + 1
        end
      end

      class UnavailableRateLimitBackend
        def increment(*)
          raise IOError, "backend unavailable"
        end
      end

      def post_image(annotation: @annotation, project: @project, token: ALICE_TOKEN, body: "Use this layout",
        bytes: @bytes, media_type: "image/png", filename: "upload.png", key: @key,
        digest: Digest::SHA256.hexdigest(bytes), include_image: true, image_count: 1,
        use_scalar_image_name: false)
        uploads = Array.new(image_count) { uploaded_file(bytes, media_type:, filename:) }
        params = { project_id: project.id, body: body }
        if use_scalar_image_name
          params[:image] = uploads.first
        elsif include_image
          params[:images] = uploads
        end

        headers = auth_headers(token)
        headers["Idempotency-Key"] = key if key
        headers["Screenote-Image-SHA256"] = digest if digest
        post raw_image_comments_path(annotation), params:, headers:
      ensure
        uploads&.each { |upload| upload.tempfile.close! }
      end

      def uploaded_file(bytes, media_type:, filename:)
        file = Tempfile.new([ "image-comment-request-", File.extname(filename) ])
        file.binmode
        file.write(bytes)
        file.close
        Rack::Test::UploadedFile.new(file.path, media_type, true, original_filename: filename)
      ensure
        file&.unlink
      end

      def raw_image_comments_path(annotation = @annotation)
        "/api/v1/annotations/#{annotation.id}/image_comments"
      end

      def auth_headers(token)
        token ? { "Authorization" => "Bearer #{token}" } : {}
      end

      def assert_capability
        assert_equal CAPABILITY, response.headers.fetch("Screenote-API-Capability")
      end

      def oauth_token(user:, scopes:)
        create_oauth_token(application: create_oauth_application, user:, scopes:)
      end

      def with_rate_limit_backend(backend)
        @controller_class.cache_store = backend
        yield
      ensure
        @controller_class.cache_store = ActiveSupport::Cache::MemoryStore.new
      end
    end
  end
end
