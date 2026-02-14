# frozen_string_literal: true

require "test_helper"

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test_secret"
  end

  teardown do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  test "rejects invalid signature" do
    post stripe_webhooks_path,
      params: "{}",
      headers: { "HTTP_STRIPE_SIGNATURE" => "invalid", "CONTENT_TYPE" => "application/json" }
    assert_response :bad_request
  end
end
