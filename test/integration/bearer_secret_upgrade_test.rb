# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class BearerSecretUpgradeTest < ActiveSupport::TestCase
  test "new OAuth and project credentials are digest-only at rest and remain usable by raw lookup" do
    application = create_oauth_application(name: "U8 bearer storage", confidential: true)
    raw_application_secret = application.plaintext_secret
    token = create_oauth_token(application: application, user: users(:alice))
    raw_access_token = token.token
    api_key = ApiKey.create!(
      project: projects(:alice_project),
      issued_by_user: users(:alice),
      name: "U8 bearer storage"
    )
    raw_api_key = api_key.raw_token

    assert_equal Digest::SHA256.hexdigest(raw_application_secret), application.reload[:secret]
    assert_equal Digest::SHA256.hexdigest(raw_access_token), token.reload[:token]
    assert_equal Digest::SHA256.hexdigest(raw_api_key), api_key.reload.token_digest
    assert_equal token, Doorkeeper::AccessToken.by_token(raw_access_token)
    assert_equal api_key, ApiKey.find_by_token(raw_api_key)

    persisted = [
      application[:secret], token[:token], api_key.token_digest
    ].join("\n")
    [ raw_application_secret, raw_access_token, raw_api_key ].each do |raw|
      assert_not_includes persisted, raw
    end
  end

  test "authentication link bearer appears only after the URL fragment boundary" do
    secret = SecureRandom.random_bytes(AuthenticationLinks::Presentation::SECRET_BYTES)
    presentation = AuthenticationLinks::Presentation.new(
      origin: "https://screenote.example",
      purpose: :password_reset,
      secret_bytes: secret
    )
    public_url, fragment = presentation.url.split("#", 2)

    assert_equal "https://screenote.example/authentication-links/password_reset", public_url
    assert_equal presentation.fragment, fragment
    assert_not_includes public_url, presentation.fragment
    assert_equal "[FILTERED]", presentation.as_json
    assert_not_includes presentation.inspect, presentation.fragment
  end

  test "HTTP parameter filtering covers every bearer-shaped field family" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(
      "access_token" => "access-token-sentinel",
      "refresh_token" => "refresh-token-sentinel",
      "client_secret" => "client-secret-sentinel",
      "upload_credential" => "upload-credential-sentinel",
      "device_code" => "device-code-sentinel"
    )

    assert_equal [ "[FILTERED]" ], filtered.values.uniq
  end
end
