# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class BootstrapControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  BOOTSTRAP_TOKEN = "bootstrap-token-#{'c' * 32}"
  VALID_PASSWORD = "correct horse battery staple"

  setup do
    skip "bootstrap routes are intentionally absent in SaaS mode" unless bootstrap_routes_drawn?

    @previous_deployment = Screenote::Deployment.current
    Screenote::Deployment.instance_variable_set(:@current, self_hosted_deployment)
    @original_rate_limit_backend = BootstrapController.cache_store
    @rate_limit_backend = ActiveSupport::Cache::MemoryStore.new
    BootstrapController.cache_store = @rate_limit_backend
    clean_bootstrap_records
    @baseline_session_ids = Session.ids
    @installation = Installations::Prepare.call(deployment: self_hosted_deployment)
  end

  teardown do
    return unless defined?(@previous_deployment)

    InstallationAuditEvent.delete_all
    Installation.delete_all
    Session.where.not(id: @baseline_session_ids).delete_all if @baseline_session_ids
    User.where(email: "controller-bootstrap@example.test").destroy_all
    BootstrapController.cache_store = @original_rate_limit_backend
    Screenote::Deployment.instance_variable_set(:@current, @previous_deployment)
    Current.reset
  end

  test "unclaimed root renders an accessible bootstrap form with defensive headers" do
    get root_path

    assert_response :success
    assert_security_headers
    assert_select "h1", text: /Set up Screenote/
    assert_select "form[action='#{bootstrap_path}'][method='post']"
    assert_select "label[for='bootstrap_token']", text: /Bootstrap token/
    assert_select "input#bootstrap_token[name='bootstrap[token]'][type='password'][required]"
    assert_select "label[for='bootstrap_email']", text: "Email"
    assert_select "input#bootstrap_email[name='bootstrap[email]'][type='email'][required]"
    assert_select "label[for='bootstrap_password']", text: "Password"
    assert_select "input#bootstrap_password[name='bootstrap[password]'][type='password'][required]"
    assert_select "label[for='bootstrap_password_confirmation']", text: /Confirm password/
    assert_select "input#bootstrap_password_confirmation[name='bootstrap[password_confirmation]'][type='password'][required]"
    assert_select "a", text: /Get Started/i, count: 0
  end

  test "successful claim creates the session only after the committed result returns" do
    email = "controller-bootstrap@example.test"
    session_count_during_call = nil
    original = Installations::Claim.method(:call)

    with_singleton_method_stub(Installations::Claim, :call, lambda { |**arguments|
      result = original.call(**arguments)
      session_count_during_call = result.user.sessions.count if result.claimed?
      result
    }) do
      assert_difference [ "User.count", "Session.count", "InstallationAuditEvent.count" ], 1 do
        post bootstrap_path, params: bootstrap_params(email:)
      end
    end

    assert_equal 0, session_count_during_call
    assert_redirected_to dashboard_path
    assert_equal email, User.find_by!(email:).email
    assert_equal User.find_by!(email:), @installation.reload.administrator
    assert_security_headers
    assert_match(/session_token=/, Array(response.headers.fetch("Set-Cookie")).join("\n"))
  end

  test "invalid token and invalid form render associated errors without a session" do
    assert_no_difference [ "User.count", "Session.count", "InstallationAuditEvent.count" ] do
      post bootstrap_path, params: bootstrap_params(token: "wrong-token")
    end

    assert_response :unprocessable_content
    assert_security_headers
    assert_select "#bootstrap_token_error[role='alert']", text: /invalid/i
    assert_select "input#bootstrap_token[aria-invalid='true'][aria-describedby='bootstrap_token_error']"
    assert_no_match "wrong-token", response.body

    @rate_limit_backend.clear
    assert_no_difference [ "User.count", "Session.count", "InstallationAuditEvent.count" ] do
      post bootstrap_path, params: bootstrap_params(password: "short", password_confirmation: "different")
    end

    assert_response :unprocessable_content
    assert_select "#bootstrap_password_error[role='alert']"
    assert_not cookies[:session_token]
    assert @installation.reload.unclaimed?
  end

  test "existing email is rejected without creating a session" do
    assert_no_difference [ "User.count", "Session.count", "InstallationAuditEvent.count" ] do
      post bootstrap_path, params: bootstrap_params(email: "  #{users(:alice).email.upcase}  ")
    end

    assert_response :unprocessable_content
    assert_select "#bootstrap_email_error[role='alert']", text: /already/i
    assert @installation.reload.unclaimed?
  end

  test "blank email uses the anonymous rate-limit identity and preserves the submitted value" do
    assert_no_difference [ "User.count", "Session.count", "InstallationAuditEvent.count" ] do
      post bootstrap_path, params: bootstrap_params(email: "")
    end

    assert_response :unprocessable_content
    assert_select "#bootstrap_email_error[role='alert']", text: /blank/i
    assert_select "input#bootstrap_email[value='']"
    assert @installation.reload.unclaimed?
  end

  test "claimed installations redirect to sign in or the signed in dashboard" do
    administrator = users(:alice)
    @installation.update!(
      state: "claimed",
      administrator:,
      claimed_at: Time.current,
      bootstrap_token_digest: nil
    )

    get root_path
    assert_redirected_to new_session_path
    assert_security_headers

    sign_in administrator
    get root_path
    assert_redirected_to dashboard_path
    assert_security_headers
  end

  test "a concurrent claim redirects using the now-claimed installation state" do
    result = Installations::Claim::Result.new(status: :already_claimed)

    with_singleton_method_stub(Installations::Claim, :call, ->(**) { result }) do
      post bootstrap_path, params: bootstrap_params
    end

    assert_redirected_to new_session_path
    assert_security_headers
    assert_not cookies[:session_token]
  end

  test "missing or SaaS installation state returns not found" do
    Installation.delete_all
    get bootstrap_path
    assert_response :not_found
    assert_security_headers

    Installations::Prepare.call(deployment: saas_deployment)
    Screenote::Deployment.instance_variable_set(:@current, saas_deployment)
    get bootstrap_path
    assert_response :not_found
    assert_security_headers
  end

  test "rate limiting is bounded and fails closed when its backend is unavailable" do
    5.times do
      post bootstrap_path, params: bootstrap_params(token: "wrong-token")
      assert_response :unprocessable_content
    end

    assert_no_difference [ "User.count", "Session.count", "InstallationAuditEvent.count" ] do
      post bootstrap_path, params: bootstrap_params(token: "wrong-token")
    end
    assert_response :too_many_requests
    assert_equal "3600", response.headers["Retry-After"]
    assert_security_headers

    @rate_limit_backend.clear
    with_singleton_method_stub(
      @rate_limit_backend,
      :increment,
      ->(*) { raise Screenote::RateLimitStore::Unavailable, "unavailable" }
    ) do
      assert_no_difference [ "User.count", "Session.count", "InstallationAuditEvent.count" ] do
        post bootstrap_path, params: bootstrap_params
      end
    end
    assert_response :service_unavailable
    assert_equal "60", response.headers["Retry-After"]
    assert_security_headers
  end

  test "busy and unavailable claim results fail closed with retry guidance" do
    {
      retryable_busy: "Setup is busy. Please retry in a moment.",
      unavailable: "Setup is temporarily unavailable."
    }.each do |status, message|
      @rate_limit_backend.clear
      result = Installations::Claim::Result.new(status: status)

      with_singleton_method_stub(Installations::Claim, :call, ->(**) { result }) do
        post bootstrap_path, params: bootstrap_params
      end

      assert_response :service_unavailable
      assert_equal "60", response.headers["Retry-After"]
      assert_select "[role='alert']", text: message
      assert_security_headers
      assert_not cookies[:session_token]
    end
  end

  private

  def bootstrap_params(
    token: BOOTSTRAP_TOKEN,
    email: "controller-bootstrap@example.test",
    password: VALID_PASSWORD,
    password_confirmation: VALID_PASSWORD
  )
    { bootstrap: { token:, email:, password:, password_confirmation: } }
  end

  def bootstrap_routes_drawn?
    Rails.application.routes.url_helpers.respond_to?(:bootstrap_path)
  end

  def assert_security_headers
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  def self_hosted_deployment
    @self_hosted_deployment ||= Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal",
        "SECRET_KEY_BASE" => "a" * 64,
        "SCREENOTE_BOOTSTRAP_TOKEN" => BOOTSTRAP_TOKEN
      },
      production: true
    )
  end

  def saas_deployment
    @saas_deployment ||= Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "saas",
        "SCREENOTE_BASE_URL" => "http://screenote.internal"
      },
      production: false
    )
  end

  def with_singleton_method_stub(object, method_name, replacement)
    singleton = object.singleton_class
    original = object.method(method_name)
    singleton.define_method(method_name, replacement)
    yield
  ensure
    singleton&.define_method(method_name, original)
  end

  def clean_bootstrap_records
    InstallationAuditEvent.delete_all
    Installation.delete_all
    User.where(email: "controller-bootstrap@example.test").destroy_all
  end
end
