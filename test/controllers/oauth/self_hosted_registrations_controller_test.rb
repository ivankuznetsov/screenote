# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

module Oauth
  class SelfHostedRegistrationsControllerTest < ActionDispatch::IntegrationTest
    self.use_transactional_tests = false

    setup do
      require_deployment_mode!(:self_hosted)
      @previous_deployment = Screenote::Deployment.current
      @deployment = Screenote::Deployment.new(
        {
          "SCREENOTE_EDITION" => "self_hosted",
          "SCREENOTE_BASE_URL" => "http://screenote.internal",
          "SECRET_KEY_BASE" => "a" * 64
        },
        production: true
      )
      Screenote::Deployment.instance_variable_set(:@current, @deployment)
      InstallationAuditEvent.delete_all
      Installation.delete_all
      @installation = Installations::Prepare.call(deployment: @deployment)
      @baseline_application_ids = Doorkeeper::Application.ids
      @client_suffix = SecureRandom.hex(8)
      DynamicClientRegistrationRateLimiter.reset!
    end

    teardown do
      DynamicClientRegistrationRateLimiter.reset!
      return unless defined?(@previous_deployment)

      Doorkeeper::Application.where.not(id: @baseline_application_ids).delete_all
      InstallationAuditEvent.delete_all
      Installation.delete_all
      Screenote::Deployment.instance_variable_set(:@current, @previous_deployment)
      Current.reset
    end

    test "returns not found before the installation is claimed" do
      assert_predicate @installation, :unclaimed?
      assert_no_difference "Doorkeeper::Application.count" do
        post oauth_register_path, params: {
          client_name: "Premature client #{@client_suffix}",
          redirect_uris: [ "http://127.0.0.1:3000/callback" ]
        }, as: :json
      end

      assert_response :not_found

      get "/.well-known/oauth-authorization-server"
      assert_response :success
      assert_not response.parsed_body.key?("registration_endpoint")
    end

    test "allows registration after the installation is claimed" do
      @installation.update!(
        state: "claimed",
        administrator: users(:alice),
        claimed_at: Time.current
      )

      post oauth_register_path, params: {
        client_name: "Claimed instance client #{@client_suffix}",
        redirect_uris: [ "http://127.0.0.1:3000/callback" ]
      }, as: :json

      assert_response :created
      assert response.parsed_body["client_id"].present?

      get "/.well-known/oauth-authorization-server"
      assert_response :success
      assert_equal "http://screenote.internal/oauth/register",
        response.parsed_body["registration_endpoint"]
    end
  end
end
