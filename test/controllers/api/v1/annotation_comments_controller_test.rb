# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class AnnotationCommentsControllerTest < ActionDispatch::IntegrationTest
      ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"

      test "creates an api-key-authored comment" do
        annotation = annotations(:point_annotation)

        assert_difference "AnnotationComment.count", 1 do
          post api_v1_annotation_comments_path(annotation),
            params: { body: "Taking a look" },
            headers: auth_header(ALICE_TOKEN)
        end

        assert_response :created
        body = response.parsed_body
        assert body["success"]
        assert_equal "Taking a look", body["comment"]["body"]
        assert_equal "Alice's CI Key", body["comment"]["author"]
        assert_equal api_keys(:alice_key), AnnotationComment.last.api_key
      end

      test "rejects empty comment body with validation code" do
        assert_no_difference "AnnotationComment.count" do
          post api_v1_annotation_comments_path(annotations(:point_annotation)),
            params: { body: "" },
            headers: auth_header(ALICE_TOKEN)
        end

        assert_response :unprocessable_entity
        assert_equal "validation_failed", response.parsed_body["code"]
      end

      test "does not comment on annotations outside the key project" do
        assert_no_difference "AnnotationComment.count" do
          post api_v1_annotation_comments_path(annotations(:bob_annotation)),
            params: { body: "Nope" },
            headers: auth_header(ALICE_TOKEN)
        end

        assert_response :not_found
        assert_equal "not_found", response.parsed_body["code"]
      end

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
