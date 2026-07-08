# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class PagesControllerTest < ActionDispatch::IntegrationTest
      ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"

      test "lists pages with version counts for the key project" do
        get api_v1_project_pages_path(projects(:alice_project)), headers: auth_header(ALICE_TOKEN)

        assert_response :success
        body = response.parsed_body
        homepage = body["pages"].detect { |page| page["id"] == pages(:alice_page).id }
        assert homepage
        assert_equal "Homepage Design", homepage["name"]
        assert_equal 1, homepage["version_count"]
        assert homepage["url"].present?
      end

      test "rejects mismatched project id" do
        get api_v1_project_pages_path(projects(:bob_project)), headers: auth_header(ALICE_TOKEN)

        assert_response :forbidden
        assert_equal "forbidden", response.parsed_body["code"]
      end

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
