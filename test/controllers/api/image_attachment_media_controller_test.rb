# frozen_string_literal: true

require "test_helper"

module Api
  class ImageAttachmentMediaControllerTest < ActionDispatch::IntegrationTest
    setup do
      require_vips!
      @user = users(:alice)
      @project = projects(:alice_project)
      @annotation = annotations(:point_annotation)
      @api_key = api_keys(:alice_key)
      @attachment = attach_to(@annotation)
      @token = @attachment.generate_token_for(ImageAttachment::MEDIA_TOKEN_PURPOSE)
    end

    test "an authorized bearer principal with a live token streams the bytes" do
      get media_path, headers: bearer_headers

      assert_response :success
      assert_equal "private, no-store", response.headers["Cache-Control"]
      assert_equal "nosniff", response.headers["X-Content-Type-Options"]
      assert_nil response.headers["Location"]
    end

    test "a token alone is never sufficient" do
      get media_path

      assert_response :unauthorized
    end

    test "a bearer principal without the token is refused" do
      get api_image_attachment_media_path(@attachment), headers: bearer_headers

      assert_response :not_found
    end

    test "a token for another attachment cannot be replayed against this one" do
      other = attach_to(@annotation)

      get api_image_attachment_media_path(@attachment, token: other.generate_token_for(ImageAttachment::MEDIA_TOKEN_PURPOSE)),
        headers: bearer_headers

      assert_response :not_found
    end

    test "the token expires after five minutes" do
      travel ImageAttachment::MEDIA_TOKEN_EXPIRY + 1.second do
        get media_path, headers: bearer_headers

        assert_response :not_found
      end
    end

    test "a refreshed token works after the first expires" do
      travel ImageAttachment::MEDIA_TOKEN_EXPIRY + 1.second do
        get api_image_attachment_media_path(
          @attachment, token: @attachment.generate_token_for(ImageAttachment::MEDIA_TOKEN_PURPOSE)
        ), headers: bearer_headers

        assert_response :success
      end
    end

    test "a revoked credential loses access immediately" do
      @api_key.update!(revoked_at: Time.current)

      get media_path, headers: bearer_headers

      assert_response :unauthorized
    end

    test "a credential scoped to another project is refused" do
      get media_path, headers: { "Authorization" => "Bearer #{bob_key_token}" }

      assert_response :not_found
    end

    test "a write-only OAuth principal cannot read the bytes" do
      write_only = create_oauth_token(
        application: create_oauth_application, user: @user, scopes: AuthenticatedPrincipal::WRITE_SCOPE
      )

      get media_path, headers: { "Authorization" => "Bearer #{write_only.token}" }

      assert_response :forbidden
      assert_equal "insufficient_scope", response.parsed_body["code"]
    end

    test "an attachment whose bytes are gone is refused" do
      @attachment.image.purge

      get media_path, headers: bearer_headers

      assert_response :not_found
    end

    test "an attachment whose message was deleted is refused" do
      ImageAttachment.connection.disable_referential_integrity do
        Annotation.where(id: @annotation.id).delete_all
      end

      get media_path, headers: bearer_headers

      assert_response :not_found
    end

    private

    def media_path
      api_image_attachment_media_path(@attachment, token: @token)
    end

    def bearer_headers
      { "Authorization" => "Bearer #{alice_key_token}" }
    end

    ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"
    BOB_TOKEN = "sk_proj_test_bob_key_0000000000000000000000000"

    def alice_key_token
      ALICE_TOKEN
    end

    def bob_key_token
      BOB_TOKEN
    end

    def attach_to(parent)
      batch = build_batch(user: @user, project: @project)
      attachment = ingest_image(batch: batch)
      ImageAttachments::ClaimBatch.call(batch: batch, user: @user, project: @project, parent_type: parent.class) { parent }
      attachment.reload
    end
  end
end
