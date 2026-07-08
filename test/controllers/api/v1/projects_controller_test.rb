# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ProjectsControllerTest < ActionDispatch::IntegrationTest
      ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"

      test "lists the project bound to the api key" do
        get api_v1_projects_path, headers: auth_header(ALICE_TOKEN)

        assert_response :success
        body = response.parsed_body
        assert_equal [ projects(:alice_project).id ], body["projects"].map { |project| project["id"] }
        assert_equal "api_key", body["projects"].first["role"]
        assert body["projects"].first.key?("screenshot_count")
      end

      test "returns stable unauthorized json without an api key" do
        get api_v1_projects_path

        assert_response :unauthorized
        assert_equal "Invalid or missing API key", response.parsed_body["error"]
        assert_equal "unauthorized", response.parsed_body["code"]
      end

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
