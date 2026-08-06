# frozen_string_literal: true

require "test_helper"

class SaasPostgresqlContractTest < ActiveSupport::TestCase
  setup do
    require_deployment_mode!(:saas)
    require_postgresql!
  end

  test "matrix is connected to the pinned PostgreSQL 16 server" do
    version_number = ActiveRecord::Base.connection.select_value("SHOW server_version_num").to_i

    assert_equal 16, version_number / 10_000,
      "SaaS qualification must run on PostgreSQL 16, got #{version_number}"
    assert Screenote::Deployment.current.billing?
    assert_equal :rabata, Screenote::Deployment.current.active_storage_service
  end

  test "hosted billing and shared core persist in one PostgreSQL transaction" do
    user = User.create!(
      email: "saas-postgresql@example.test",
      password: "password123",
      confirmed_at: Time.current
    )
    subscription = Subscription.create!(
      user: user,
      stripe_customer_id: "cus_u8_postgresql",
      stripe_subscription_id: "sub_u8_postgresql",
      plan: :pro,
      status: :active,
      current_period_end: 1.month.from_now
    )
    project = Projects::Create.call(
      principal: AuthenticatedPrincipal.for_user(user),
      attributes: { name: "PostgreSQL shared core" }
    )
    page = project.pages.create!(name: "/postgresql")
    screenshot = page.screenshots.create!(title: "PostgreSQL contract")
    annotation = screenshot.annotations.create!(
      user: user,
      comment: "PostgreSQL actor invariant",
      x_percent: 15.0,
      y_percent: 25.0,
      viewport: :desktop
    )

    assert subscription.persisted?
    assert project.persisted?
    assert annotation.persisted?
    assert_equal user, annotation.user
    assert_nil annotation.api_key
  end

  test "SaaS routes expose hosted capabilities and exclude instance administration" do
    helpers = Rails.application.routes.url_helpers

    assert_respond_to helpers, :subscription_path
    assert_respond_to helpers, :admin_dashboard_path
    assert_respond_to helpers, :stripe_webhooks_path
    assert_not_respond_to helpers, :bootstrap_path
    assert_not_respond_to helpers, :instance_accounts_path
  end
end
