# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require_relative "../support/instance_administration_test_helper"

class AccountRecoveriesControllerTest < ActionDispatch::IntegrationTest
  include InstanceAdministrationTestHelper
  self.use_transactional_tests = false

  setup do
    skip "account recovery routes are absent in SaaS mode" unless account_recovery_routes_drawn?

    @original_rate_limit_backend = AccountRecoveriesController.cache_store
    @rate_limit_backend = ActiveSupport::Cache::MemoryStore.new
    AccountRecoveriesController.cache_store = @rate_limit_backend
    @administrator = users(:alice)
    @target = users(:bob)
    prepare_claimed_installation(administrator: @administrator)
    @target.update!(access_status: :active)
    @issued = create_recovery_token(subject: @target, issuer: @administrator)
  end

  teardown do
    return unless account_recovery_routes_drawn?

    AuthenticationToken.delete_all
    InstallationAuditEvent.delete_all
    Installation.delete_all
    AccountRecoveriesController.cache_store = @original_rate_limit_backend
    Current.reset
  end

  test "tokenless recovery form consumes context once and creates a new session after commit" do
    raw = @issued.presentation.fragment
    post exchange_authentication_link_path(:account_recovery), params: { token: raw }

    assert_redirected_to account_recovery_path
    assert_equal(
      { "token_id" => @issued.token.id, "purpose" => "account_recovery" },
      session[:authentication_link]
    )
    assert_not_includes response.location, raw

    get account_recovery_path
    assert_response :success
    assert_private_headers
    assert_select "form[action='#{account_recovery_path}'][method='post']"
    assert_select "input[name='account_recovery[password]'][type='password'][required]"
    assert_select "input[name='account_recovery[password_confirmation]'][type='password'][required]"
    assert_not_includes response.body, raw

    assert_difference -> { InstallationAuditEvent.where(event_type: "account_recovered").count }, 1 do
      post account_recovery_path, params: {
        account_recovery: {
          password: "new correct horse battery staple",
          password_confirmation: "new correct horse battery staple"
        }
      }
    end

    assert_redirected_to dashboard_path
    assert_nil session[:authentication_link]
    assert @issued.token.reload.consumed?
    assert @target.reload.authenticate("new correct horse battery staple")
    assert cookies[:session_token]
    assert_not_includes cookies.to_s, raw
  end

  test "invalid password keeps token context and renders associated errors" do
    post exchange_authentication_link_path(:account_recovery), params: { token: @issued.presentation.fragment }

    post account_recovery_path, params: {
      account_recovery: { password: "short", password_confirmation: "different" }
    }

    assert_response :unprocessable_content
    assert_equal @issued.token.id, session.dig(:authentication_link, "token_id")
    assert @issued.token.reload.outstanding?
    assert_select "[data-testid='recovery-errors'][role='alert']"
    assert_select "input#account_recovery_password[aria-invalid='true']"
  end

  test "terminal or missing context reveals no account identity and clears context" do
    get account_recovery_path
    assert_response :unprocessable_content
    assert_not_includes response.body, @target.email

    post exchange_authentication_link_path(:account_recovery), params: { token: @issued.presentation.fragment }
    @issued.token.transition_to!(:cancelled)
    get account_recovery_path

    assert_response :unprocessable_content
    assert_nil session[:authentication_link]
    assert_not_includes response.body, @target.email
  end

  test "transient revalidation after invalid input retains context and returns retryable response" do
    post exchange_authentication_link_path(:account_recovery), params: { token: @issued.presentation.fragment }
    original_consume = AccountRecoveries::Consume.method(:call)
    original_validate = AccountRecoveries::Validate.method(:call)
    AccountRecoveries::Consume.define_singleton_method(:call) do |**|
      InstanceAdministration::Result.new(status: :invalid, errors: { password: [ "is invalid" ] })
    end
    AccountRecoveries::Validate.define_singleton_method(:call) do |**|
      InstanceAdministration::Result.new(status: :retryable_busy)
    end

    post account_recovery_path, params: {
      account_recovery: { password: "new-password", password_confirmation: "new-password" }
    }

    assert_response :service_unavailable
    assert_equal AccountRecoveriesController::RATE_LIMIT_RETRY_AFTER.to_s, response.headers["Retry-After"]
    assert_equal @issued.token.id, session.dig(:authentication_link, "token_id")
    assert_select "[data-testid='recovery-errors'][role='alert']", text: /temporarily unavailable/i
  ensure
    AccountRecoveries::Consume.define_singleton_method(:call, original_consume) if original_consume
    AccountRecoveries::Validate.define_singleton_method(:call, original_validate) if original_validate
  end

  test "show retains context when validation is temporarily unavailable" do
    exchange_recovery_link

    %i[retryable_busy unavailable].each do |status|
      result = InstanceAdministration::Result.new(status: status)

      with_singleton_method(AccountRecoveries::Validate, :call, ->(**) { result }) do
        get account_recovery_path
      end

      assert_response :service_unavailable
      assert_equal AccountRecoveriesController::RATE_LIMIT_RETRY_AFTER.to_s, response.headers["Retry-After"]
      assert_equal @issued.token.id, session.dig(:authentication_link, "token_id")
      assert_not_includes response.body, @target.email
    end
  end

  test "invalid input clears context when revalidation becomes terminal" do
    exchange_recovery_link
    consume_result = InstanceAdministration::Result.new(
      status: :invalid,
      errors: { password: [ "is invalid" ] }
    )
    validation_result = InstanceAdministration::Result.new(status: :expired)

    with_singleton_method(AccountRecoveries::Consume, :call, ->(**) { consume_result }) do
      with_singleton_method(AccountRecoveries::Validate, :call, ->(**) { validation_result }) do
        post account_recovery_path, params: {
          account_recovery: { password: "invalid-password", password_confirmation: "invalid-password" }
        }
      end
    end

    assert_response :unprocessable_content
    assert_nil session[:authentication_link]
    assert_not_includes response.body, @target.email
  end

  test "consume retry and terminal results have distinct context lifecycles" do
    exchange_recovery_link

    %i[retryable_busy unavailable].each do |status|
      result = InstanceAdministration::Result.new(status: status)
      with_singleton_method(AccountRecoveries::Consume, :call, ->(**) { result }) do
        post account_recovery_path
      end

      assert_response :service_unavailable
      assert_equal @issued.token.id, session.dig(:authentication_link, "token_id")
    end

    terminal = InstanceAdministration::Result.new(status: :expired)
    with_singleton_method(AccountRecoveries::Consume, :call, ->(**) { terminal }) do
      post account_recovery_path
    end

    assert_response :unprocessable_content
    assert_nil session[:authentication_link]
  end

  test "POST without exchange context is sterile" do
    assert_no_difference [ "AuthenticationToken.count", "Session.count" ] do
      post account_recovery_path, params: {
        account_recovery: { password: "replacement-password", password_confirmation: "replacement-password" }
      }
    end

    assert_response :unprocessable_content
    assert_nil session[:authentication_link]
    assert_not_includes response.body, @target.email
    assert_private_headers
  end

  test "rate limits repeated recovery attempts by token and IP" do
    exchange_recovery_link
    consume_result = InstanceAdministration::Result.new(status: :retryable_busy)

    with_singleton_method(AccountRecoveries::Consume, :call, ->(**) { consume_result }) do
      AccountRecoveriesController::RATE_LIMIT.times do
        post account_recovery_path
        assert_response :service_unavailable
      end

      post account_recovery_path
    end

    assert_response :too_many_requests
    assert_equal AccountRecoveriesController::RATE_LIMIT_WINDOW.to_i.to_s, response.headers["Retry-After"]
    assert_equal @issued.token.id, session.dig(:authentication_link, "token_id")
    assert_select "[data-testid='recovery-errors'][role='alert']", text: /too many recovery attempts/i
  end

  test "rate-limit backend failure fails closed without consuming recovery context" do
    exchange_recovery_link
    unavailable = ->(*, **) { raise Screenote::RateLimitStore::Unavailable, "offline" }

    with_singleton_method(@rate_limit_backend, :increment, unavailable) do
      post account_recovery_path
    end

    assert_response :service_unavailable
    assert_equal AccountRecoveriesController::RATE_LIMIT_RETRY_AFTER.to_s, response.headers["Retry-After"]
    assert_equal @issued.token.id, session.dig(:authentication_link, "token_id")
    assert_private_headers
  end

  private

  def account_recovery_routes_drawn?
    Rails.application.routes.url_helpers.respond_to?(:account_recovery_path)
  end

  def exchange_recovery_link
    post exchange_authentication_link_path(:account_recovery), params: { token: @issued.presentation.fragment }
    assert_redirected_to account_recovery_path
  end

  def with_singleton_method(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, implementation)
    yield
  ensure
    object.define_singleton_method(name, original) if original
  end

  def assert_private_headers
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end
end
