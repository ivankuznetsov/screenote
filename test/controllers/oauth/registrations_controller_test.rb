# frozen_string_literal: true

require "test_helper"

module Oauth
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    test "creates a client with valid parameters" do
      assert_difference "Doorkeeper::Application.count", 1 do
        post oauth_register_path, params: {
          client_name: "Test MCP Client",
          redirect_uris: [ "http://localhost:3000/callback" ]
        }, as: :json
      end

      assert_response :created
      json = JSON.parse(response.body)

      assert_equal "Test MCP Client", json["client_name"]
      assert_equal [ "http://localhost:3000/callback" ], json["redirect_uris"]
      assert json["client_id"].present?, "Should return a client_id"
      assert_equal [ "authorization_code" ], json["grant_types"]
      assert_equal "none", json["token_endpoint_auth_method"]

      app = Doorkeeper::Application.last
      assert app.dynamic?, "Application should be flagged as dynamic"
      assert_not app.confidential?, "Application should be public (non-confidential)"
    end

    test "creates a client with default name when client_name is blank" do
      post oauth_register_path, params: {
        redirect_uris: [ "http://localhost:3000/callback" ]
      }, as: :json

      assert_response :created
      json = JSON.parse(response.body)
      assert_equal "MCP Client", json["client_name"]
    end

    test "returns error when redirect_uris is missing" do
      assert_no_difference "Doorkeeper::Application.count" do
        post oauth_register_path, params: {
          client_name: "Bad Client"
        }, as: :json
      end

      assert_response :bad_request
      json = JSON.parse(response.body)
      assert_equal "invalid_client_metadata", json["error"]
    end

    test "returns error when redirect_uris is empty array" do
      assert_no_difference "Doorkeeper::Application.count" do
        post oauth_register_path, params: {
          client_name: "Bad Client",
          redirect_uris: []
        }, as: :json
      end

      assert_response :bad_request
    end

    test "does not require authentication" do
      post oauth_register_path, params: {
        client_name: "Public Client",
        redirect_uris: [ "http://localhost/callback" ]
      }, as: :json

      assert_response :created, "DCR endpoint should be public"
    end

    test "supports multiple redirect URIs" do
      post oauth_register_path, params: {
        client_name: "Multi-Redirect",
        redirect_uris: [ "http://localhost:3000/cb1", "http://localhost:3000/cb2" ]
      }, as: :json

      assert_response :created
      json = JSON.parse(response.body)
      assert_equal 2, json["redirect_uris"].length
    end
  end
end
