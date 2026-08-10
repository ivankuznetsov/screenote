# frozen_string_literal: true

require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @rate_limit_backend = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store = @rate_limit_backend
    @email = "registration-controller-#{SecureRandom.hex(6)}@example.test"
    clear_enqueued_jobs
  end

  teardown do
    User.where(email: @email).find_each(&:destroy!)
    clear_enqueued_jobs
    Current.reset
  end

  test "new renders for guests and redirects signed-in users" do
    get sign_up_path
    assert_response :success
    assert_select "form[action='#{sign_up_path}'][method='post']"

    sign_in(users(:alice))
    get sign_up_path
    assert_redirected_to dashboard_path
  end

  test "blank email and invalid attributes render errors without retrying admission" do
    assert_no_difference "User.count" do
      post sign_up_path, params: {
        user: { email: "", password: "short", password_confirmation: "different" }
      }
    end

    assert_response :unprocessable_content
    assert_select ".auth-card__field-error"
  end

  test "an existing normalized email renders a duplicate error" do
    assert_no_difference "User.count" do
      post sign_up_path, params: {
        user: {
          email: users(:alice).email.upcase,
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_response :unprocessable_content
    assert_select ".auth-card__field-error", text: /already been taken/i
  end

  test "duplicate fallback adds an error when validation did not" do
    candidate = User.new
    candidate.define_singleton_method(:valid?) { true }

    with_singleton_method(User, :new, ->(*, **) { candidate }) do
      post sign_up_path, params: {
        user: {
          email: users(:alice).email,
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_response :unprocessable_content
    assert_equal [ "has already been taken" ], candidate.errors[:email]
  end

  test "duplicate fallback does not add the same validation error twice" do
    candidate = User.new
    candidate.errors.add(:email, :taken)
    candidate.define_singleton_method(:valid?) { true }

    with_singleton_method(User, :new, ->(*, **) { candidate }) do
      post sign_up_path, params: {
        user: {
          email: users(:alice).email,
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_response :unprocessable_content
    assert_equal [ "has already been taken" ], candidate.errors[:email]
  end

  test "failed confirmation issuance leaves a recoverable account" do
    issuance = UserAuthenticationLinks::Issue::Result.new(status: :unavailable)

    with_singleton_method(UserAuthenticationLinks::Issue, :call, ->(**) { issuance }) do
      assert_difference "User.count", 1 do
        post sign_up_path, params: { user: valid_attributes }
      end
    end

    assert_redirected_to new_confirmation_path
    assert_equal(
      "Account created, but confirmation email could not be sent. Please request another.",
      flash[:alert]
    )
    assert User.find_by!(email: @email).unconfirmed?
  end

  test "a SaaS runtime without mail signs the new account in" do
    deployment = saas_mail_disabled_deployment
    with_singleton_method(Screenote::Deployment, :current, -> { deployment }) do
      assert_difference [ "User.count", "Session.count" ], 1 do
        post sign_up_path, params: { user: valid_attributes }
      end
    end

    assert_redirected_to dashboard_path
    assert User.find_by!(email: @email).sessions.exists?
  end

  test "database retry exhaustion renders a retryable error" do
    exhausted = DatabaseRetry::Exhausted.new(ActiveRecord::Deadlocked.new, attempts: 3)
    failure = ->(**, &) { raise exhausted }

    with_singleton_method(DatabaseRetry, :call, failure) do
      assert_no_difference "User.count" do
        post sign_up_path, params: { user: valid_attributes }
      end
    end

    assert_response :service_unavailable
    assert_select ".auth-card__error", text: /Screenote is busy/i
  end

  test "edition capability drift returns not found" do
    deployment = self_hosted_deployment
    with_singleton_method(Screenote::Deployment, :current, -> { deployment }) do
      get sign_up_path
    end

    assert_response :not_found
  end

  test "sign-up attempts are rate limited by client IP" do
    5.times do
      post sign_up_path, params: {
        user: { email: "", password: "short", password_confirmation: "different" }
      }
      assert_response :unprocessable_content
    end

    post sign_up_path, params: {
      user: { email: "", password: "short", password_confirmation: "different" }
    }

    assert_redirected_to sign_up_path
    assert_match(/too many sign up attempts/i, flash[:alert])
  end

  test "sign-up attempts fail closed when the rate-limit backend is unavailable" do
    unavailable = ->(*, **) { raise IOError, "offline" }

    with_singleton_method(@rate_limit_backend, :increment, unavailable) do
      assert_no_difference "User.count" do
        post sign_up_path, params: { user: valid_attributes }
      end
    end

    assert_response :service_unavailable
    assert_equal "60", response.headers["Retry-After"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_no_enqueued_emails
  end

  private

  def valid_attributes
    {
      email: @email.upcase,
      password: "password123",
      password_confirmation: "password123"
    }
  end

  def saas_mail_disabled_deployment
    Object.new.tap do |deployment|
      deployment.define_singleton_method(:saas?) { true }
      deployment.define_singleton_method(:mail?) { false }
      deployment.define_singleton_method(:billing?) { false }
      deployment.define_singleton_method(:secure_cookies?) { false }
    end
  end

  def self_hosted_deployment
    Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal"
      },
      production: false
    )
  end

  def with_singleton_method(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, implementation)
    yield
  ensure
    object.define_singleton_method(name, original) if original
  end
end
