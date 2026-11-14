# frozen_string_literal: true

require "test_helper"

module Oauth
  class AuthorizationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:alice)
      @project = projects(:alice_project)
      @application = create_oauth_application(name: "Consent client", redirect_uri: "http://127.0.0.1:9999/callback")
      _verifier, @code_challenge = generate_pkce_challenge
      sign_in(@user)
    end

    test "authorize form submits the requested response mode" do
      get "/oauth/authorize", params: authorization_params(response_mode: "fragment")

      assert_response :success
      assert_select "form.oauth-consent__form input[type='hidden'][name='response_mode'][value='fragment']"
      assert_select "form.oauth-consent__deny input[type='hidden'][name='response_mode'][value='fragment']"
    end

    test "quota rejection keeps the submitted project selected" do
      exceeded = ->(**) { raise DynamicClientAuthorizationQuota::Exceeded, "Revoke an unused client first." }

      with_singleton_method(DynamicClientAuthorizationQuota, :authorize, exceeded) do
        assert_no_difference "Doorkeeper::AccessGrant.count" do
          post "/oauth/authorize", params: authorization_params.merge(principal_project_id: @project.id)
        end
      end

      assert_response :unprocessable_entity
      assert_select "[data-testid='oauth-principal-error']", text: "Revoke an unused client first."
      assert_select "select[data-testid='oauth-principal-select'] option[selected][value='#{@project.id}']"
    end

    test "quota rejection of an account grant keeps the account selected" do
      exceeded = ->(**) { raise DynamicClientAuthorizationQuota::Exceeded, "Revoke an unused client first." }

      with_singleton_method(DynamicClientAuthorizationQuota, :authorize, exceeded) do
        post "/oauth/authorize", params: authorization_params.merge(principal_project_id: "")
      end

      assert_response :unprocessable_entity
      assert_select "select[data-testid='oauth-principal-select'] option[selected]", count: 0
    end

    private

    def authorization_params(**overrides)
      {
        client_id: @application.uid,
        redirect_uri: @application.redirect_uri,
        response_type: "code",
        scope: "mcp_read",
        code_challenge: @code_challenge,
        code_challenge_method: "S256",
        state: "consent-state"
      }.merge(overrides)
    end
  end
end
