# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class SelfHostedCapabilityBoundaryTest < ActionDispatch::IntegrationTest
  setup do
    @previous_deployment = Screenote::Deployment.current
    Screenote::Deployment.instance_variable_set(:@current, self_hosted_deployment)
  end

  teardown do
    Screenote::Deployment.instance_variable_set(:@current, @previous_deployment)
  end

  test "projects render unlimited core without billing queries, links, or hosted support copy" do
    sign_in(users(:bob))

    queries = capture_queries { get projects_path }

    assert_response :success
    assert_select "a", text: "New project"
    assert_select "a", text: /Upgrade|Billing/, count: 0
    assert_select "[data-testid='upgrade-banner']", count: 0
    assert_select "a[href='mailto:support@screenote.ai']", count: 0
    assert_empty queries.grep(/\bsubscriptions\b/i)
  end

  test "hosted commercial and operator endpoints fail closed without invoking Stripe" do
    sign_in(users(:admin))
    original_construct_event = Stripe::Webhook.method(:construct_event)
    stripe_called = false
    Stripe::Webhook.define_singleton_method(:construct_event) do |*|
      stripe_called = true
      raise "Stripe must be inert in self-hosted mode"
    end

    get "/subscription"
    assert_response :not_found
    get "/admin/dashboard"
    assert_response :not_found
    get "/terms"
    assert_response :not_found
    get "/privacy"
    assert_response :not_found
    post "/stripe/webhooks", headers: { "Stripe-Signature" => "unused" }
    assert_response :not_found
    assert_not stripe_called
  ensure
    Stripe::Webhook.define_singleton_method(:construct_event, original_construct_event)
  end

  private

  def self_hosted_deployment
    Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal",
        "SECRET_KEY_BASE" => "a" * 64,
        "SCREENOTE_BOOTSTRAP_TOKEN" => "b" * 43
      },
      production: true
    )
  end

  def capture_queries
    queries = []
    callback = lambda do |_name, _started, _finished, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      queries << payload.fetch(:sql)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end
end
