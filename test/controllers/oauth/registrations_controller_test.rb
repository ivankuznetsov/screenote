# frozen_string_literal: true

require "test_helper"

module Oauth
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    DEVICE_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code"

    setup do
      DynamicClientRegistrationRateLimiter.reset!
    end

    teardown do
      DynamicClientRegistrationRateLimiter.reset!
    end

    test "creates a client with valid parameters" do
      assert_difference "Doorkeeper::Application.count", 1 do
        post oauth_register_path, params: {
          client_name: "Test MCP Client",
          redirect_uris: [ "http://127.0.0.1:3000/callback" ]
        }, as: :json
      end

      assert_response :created
      json = JSON.parse(response.body)

      assert_equal "Test MCP Client", json["client_name"]
      assert_equal [ "http://127.0.0.1:3000/callback" ], json["redirect_uris"]
      assert json["client_id"].present?, "Should return a client_id"
      assert_equal [ "authorization_code", DEVICE_GRANT_TYPE, "refresh_token" ], json["grant_types"]
      assert_equal "none", json["token_endpoint_auth_method"]

      app = Doorkeeper::Application.last
      assert app.dynamic?, "Application should be flagged as dynamic"
      assert_not app.confidential?, "Application should be public (non-confidential)"
    end

    test "creates a client with default name when client_name is blank" do
      post oauth_register_path, params: {
        redirect_uris: [ "http://127.0.0.1:3000/callback" ]
      }, as: :json

      assert_response :created
      json = JSON.parse(response.body)
      assert_equal "OAuth Client", json["client_name"]
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
        redirect_uris: [ "http://127.0.0.1/callback" ]
      }, as: :json

      assert_response :created, "DCR endpoint should be public"
    end

    test "supports multiple redirect URIs" do
      post oauth_register_path, params: {
        client_name: "Multi-Redirect",
        redirect_uris: [ "http://127.0.0.1:3000/cb1", "http://127.0.0.1:3001/cb2" ]
      }, as: :json

      assert_response :created
      json = JSON.parse(response.body)
      assert_equal 2, json["redirect_uris"].length
    end

    test "accepts exact IPv4 and IPv6 loopback redirect addresses" do
      [
        "http://127.0.0.1:49152/callback",
        "http://[::1]:49153/callback"
      ].each do |redirect_uri|
        post oauth_register_path, params: {
          client_name: "Loopback #{redirect_uri}",
          redirect_uris: [ redirect_uri ]
        }, as: :json

        assert_response :created, redirect_uri
        assert_equal [ redirect_uri ], response.parsed_body["redirect_uris"]
      end
    end

    test "rejects non-exact or unsafe loopback redirect addresses" do
      [
        "http://localhost:3000/callback",
        "https://127.0.0.1:3000/callback",
        "http://user:password@127.0.0.1:3000/callback",
        "http://127.0.0.1:3000/callback#fragment",
        "http://%31%32%37.0.0.1:3000/callback",
        "http://127%2e0%2e0%2e1:3000/callback",
        "http://127.0.0.1%2f@evil.example/callback"
      ].each do |redirect_uri|
        assert_no_difference "Doorkeeper::Application.count", redirect_uri do
          post oauth_register_path, params: {
            client_name: "Unsafe redirect",
            redirect_uris: [ redirect_uri ]
          }, as: :json
        end

        assert_response :bad_request, redirect_uri
        assert_equal "invalid_client_metadata", response.parsed_body["error"]
      end
    end

    test "rejects duplicate redirect URIs" do
      redirect_uri = "http://127.0.0.1:3000/callback"

      assert_no_difference "Doorkeeper::Application.count" do
        post oauth_register_path, params: {
          client_name: "Duplicate redirects",
          redirect_uris: [ redirect_uri, redirect_uri ]
        }, as: :json
      end

      assert_response :bad_request
      assert_match(/unique/i, response.parsed_body["error_description"])
    end

    test "deduplicates equivalent registrations regardless of redirect URI order" do
      redirect_uris = [
        "http://127.0.0.1:3001/second",
        "http://127.0.0.1:3000/first"
      ]

      assert_difference "Doorkeeper::Application.count", 1 do
        post oauth_register_path, params: {
          client_name: "Idempotent client",
          redirect_uris: redirect_uris
        }, as: :json
      end
      assert_response :created
      client_id = response.parsed_body.fetch("client_id")

      assert_no_difference "Doorkeeper::Application.count" do
        post oauth_register_path, params: {
          client_name: "Idempotent client",
          redirect_uris: redirect_uris.reverse
        }, as: :json
      end
      assert_response :success
      assert_equal client_id, response.parsed_body["client_id"]
      assert_equal redirect_uris.sort, response.parsed_body["redirect_uris"]
    end

    test "fails closed when the rate-limit backend is unavailable" do
      with_unavailable_registration_rate_limit_store do
        assert_no_difference "Doorkeeper::Application.count" do
          post oauth_register_path, params: {
            client_name: "Unavailable limiter",
            redirect_uris: [ "http://127.0.0.1:3000/callback" ]
          }, as: :json
        end
      end

      assert_response :service_unavailable
      assert_equal "invalid_client_metadata", response.parsed_body["error"]
      assert_equal RegistrationsController::RATE_LIMITER_RETRY_AFTER.to_s, response.headers["Retry-After"]
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_equal "no-cache", response.headers["Pragma"]
    end

    test "returns too many requests before attempting registration when the limit is exceeded" do
      limiter = ->(**) { true }
      registration = ->(**) { raise "rate-limited requests must not register a client" }

      with_singleton_method(DynamicClientRegistrationRateLimiter, :exceeded?, limiter) do
        with_singleton_method(DynamicClientRegistration, :call, registration) do
          assert_no_difference "Doorkeeper::Application.count" do
            post oauth_register_path, params: {
              client_name: "Rate-limited client",
              redirect_uris: [ "http://127.0.0.1:3000/callback" ]
            }, as: :json
          end
        end
      end

      assert_response :too_many_requests
      assert_equal "invalid_client_metadata", response.parsed_body["error"]
      assert_equal DynamicClientRegistrationRateLimiter::WINDOW.to_i.to_s, response.headers["Retry-After"]
    end

    test "returns service unavailable when global client capacity is exhausted" do
      capacity = lambda do |**|
        raise DynamicClientRegistration::CapacityExceeded, "Dynamic client capacity reached"
      end

      with_singleton_method(DynamicClientRegistration, :call, capacity) do
        assert_no_difference "Doorkeeper::Application.count" do
          post oauth_register_path, params: {
            client_name: "Capacity client",
            redirect_uris: [ "http://127.0.0.1:3000/callback" ]
          }, as: :json
        end
      end

      assert_response :service_unavailable
      assert_equal "invalid_client_metadata", response.parsed_body["error"]
      assert_match(/capacity reached/i, response.parsed_body["error_description"])
    end

    test "returns not found when a self-hosted capability check has no installation" do
      deployment = self_hosted_deployment
      unexpected_limiter_call = ->(**) { raise "rate limiter must not run after a terminal capability check" }

      with_singleton_method(Screenote::Deployment, :current, -> { deployment }) do
        with_singleton_method(Installation, :current, -> { nil }) do
          with_singleton_method(DynamicClientRegistrationRateLimiter, :exceeded?, unexpected_limiter_call) do
            assert_no_difference "Doorkeeper::Application.count" do
              post oauth_register_path, params: {
                client_name: "Unavailable self-hosted client",
                redirect_uris: [ "http://127.0.0.1:3000/callback" ]
              }, as: :json
            end
          end
        end
      end

      assert_response :not_found
    end

    private

    def with_unavailable_registration_rate_limit_store
      store = DynamicClientRegistrationRateLimiter.send(:store)
      original_increment = store.method(:increment)
      store.define_singleton_method(:increment) { |*, **| nil }
      yield
    ensure
      store&.define_singleton_method(:increment, original_increment) if original_increment
    end

    def with_singleton_method(object, name, implementation)
      original = object.method(name)
      object.define_singleton_method(name, implementation)
      yield
    ensure
      object.define_singleton_method(name, original) if original
    end

    def self_hosted_deployment
      Screenote::Deployment.new(
        {
          "SCREENOTE_EDITION" => "self_hosted",
          "SCREENOTE_BASE_URL" => "http://screenote.internal",
          "SCREENOTE_BOOTSTRAP_TOKEN" => "b" * 43
        },
        production: false
      )
    end
  end
end
