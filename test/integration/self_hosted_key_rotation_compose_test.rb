# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "yaml"

class SelfHostedKeyRotationComposeTest < ActiveSupport::TestCase
  OVERLAY = Rails.root.join("compose.auth-link-key-rotation.yaml").freeze

  test "prior authentication-link keys are available only through one restricted secret mount" do
    overlay = YAML.safe_load(OVERLAY.read, aliases: true)
    service = overlay.dig("services", "screenote")
    secret = service.fetch("secrets").sole

    assert_equal [ "screenote" ], overlay.fetch("services").keys
    assert_equal "/run/secrets/screenote_authentication_link_prior_keys",
      service.dig("environment", "SCREENOTE_AUTHENTICATION_LINK_PRIOR_KEYS_FILE")
    assert_nil service.dig("environment", "SCREENOTE_AUTHENTICATION_LINK_PRIOR_KEYS")
    assert_equal "screenote_authentication_link_prior_keys", secret.fetch("source")
    assert_equal "screenote_authentication_link_prior_keys", secret.fetch("target")
    assert_equal "1000", secret.fetch("uid")
    assert_equal "1000", secret.fetch("gid")
    assert_equal 0o400, secret.fetch("mode")
    assert_equal [ "screenote_authentication_link_prior_keys" ], overlay.fetch("secrets").keys
  end
end
