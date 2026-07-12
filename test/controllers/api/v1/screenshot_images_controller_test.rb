# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ScreenshotImagesControllerTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"
      REVOKED_TOKEN = "sk_proj_test_alice_revoked_00000000000000000000"

      setup do
        @project = projects(:alice_project)
        @image_data = File.binread(Rails.root.join("test/fixtures/files/test_image.png"))
        @snapshot, @image = prepare_image(@image_data)
      end

      test "rate-limit budget permits one maximum manifest plus a full retry" do
        assert_operator Api::V1::ScreenshotImagesController::UPLOAD_RATE_LIMIT, :>=, Snapshots::PrepareUpload::MAX_ENTRIES * 2
      end

      test "uploads valid prepared bytes and enqueues processing" do
        upload(@image_data)

        assert_response :ok
        assert_enqueued_with(job: ScreenshotDimensionJob, args: [ @image, @image.reload.image.blob.id ])
        assert_equal "uploaded", response.parsed_body["operation"]
        assert_equal "processing", response.parsed_body["state"]
        assert @image.reload.image.attached?
        assert_equal "image/png", @image.image.blob.content_type
      end

      test "identical retry succeeds without another attachment blob or processing job" do
        upload(@image_data)
        assert_response :ok
        clear_enqueued_jobs

        assert_no_difference [ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ] do
          assert_no_enqueued_jobs only: ScreenshotDimensionJob do
            upload(@image_data)
          end
        end

        assert_response :ok
        assert_equal "already_uploaded", response.parsed_body["operation"]
      end

      test "failed processing retry returns to pending and re-enqueues without reattaching" do
        upload(@image_data)
        @image.reload.update!(status: :failed)
        clear_enqueued_jobs

        assert_no_difference [ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ] do
          assert_enqueued_with(job: ScreenshotDimensionJob, args: [ @image, @image.image.blob.id ]) do
            upload(@image_data)
          end
        end

        assert_response :ok
        assert_equal "processing_retried", response.parsed_body["operation"]
        assert @image.reload.status_pending?
      end

      test "wrong bytes conflict without replacing an existing blob" do
        upload(@image_data)
        blob_id = @image.reload.image.blob.id

        upload(@image_data + "different bytes")

        assert_response :conflict
        assert_equal "content_digest_mismatch", response.parsed_body["code"]
        assert_equal blob_id, @image.reload.image.blob.id
      end

      test "rejects empty mislabeled invalid and unsupported bodies without attaching" do
        invalid_requests = [
          [ "", "image/png", "empty_body" ],
          [ @image_data, "image/jpeg", "content_type_mismatch" ],
          [ "not an image", "image/png", "invalid_image" ],
          [ "GIF89a", "image/gif", "invalid_content_type" ]
        ]

        invalid_requests.each do |body, content_type, code|
          upload(body, content_type: content_type)
          assert_response :unprocessable_entity
          assert_equal code, response.parsed_body["code"]
          assert_not @image.reload.image.attached?
        end
      end

      test "rejects declared oversized body before attachment" do
        upload(@image_data, headers: { "Content-Length" => (ScreenshotImage::MAX_FILE_SIZE + 1).to_s })

        assert_response :unprocessable_entity
        assert_equal "file_too_large", response.parsed_body["code"]
        assert_not @image.reload.image.attached?
      end

      test "chunked oversized body is bounded and removes its temporary file" do
        process_tempfiles = Rails.root.join("tmp/screenote-upload*#{Process.pid}*")
        body = "x" * (ScreenshotImage::MAX_FILE_SIZE + 1)

        upload(body, headers: { "Transfer-Encoding" => "chunked" })

        assert_response :unprocessable_entity
        assert_equal "file_too_large", response.parsed_body["code"]
        assert_empty Dir.glob(process_tempfiles)
        assert_not @image.reload.image.attached?
      end

      test "requires write scope and matching project credentials" do
        read_token = oauth_token(users(:alice), "mcp_read")

        upload(@image_data, token: read_token.token)
        assert_response :forbidden
        assert_equal "insufficient_scope", response.parsed_body["code"]

        upload(@image_data, token: REVOKED_TOKEN)
        assert_response :unauthorized

        upload(@image_data, token: nil)
        assert_response :unauthorized

        put api_v1_project_screenshot_image_path(projects(:bob_project), @image),
          headers: auth_headers(ALICE_TOKEN, "image/png"),
          env: { "RAW_POST_DATA" => @image_data }
        assert_response :forbidden
      end

      test "OAuth write token uploads for a member project" do
        write_token = oauth_token(users(:alice), "mcp_write")

        upload(@image_data, token: write_token.token)

        assert_response :ok
        assert @image.reload.image.attached?
      end

      private

      def prepare_image(bytes)
        entry = snapshot_entry(page: "Authenticated upload", viewport: :desktop, seed: SecureRandom.hex(4))
        entry[:content_sha256] = Digest::SHA256.hexdigest(bytes)
        snapshot = Snapshots::PrepareUpload.call(
          project: @project,
          payload: snapshot_manifest_payload(entries: [ entry ])
        ).snapshot
        [ snapshot, snapshot.screenshot_images.first ]
      end

      def upload(body, content_type: "image/png", token: ALICE_TOKEN, headers: {})
        put api_v1_project_screenshot_image_path(@project, @image),
          headers: auth_headers(token, content_type).merge(headers),
          env: { "RAW_POST_DATA" => body }
      end

      def auth_headers(token, content_type)
        headers = { "Content-Type" => content_type }
        headers["Authorization"] = "Bearer #{token}" if token
        headers
      end

      def oauth_token(user, scopes)
        create_oauth_token(application: create_oauth_application, user: user, scopes: scopes)
      end
    end
  end
end
