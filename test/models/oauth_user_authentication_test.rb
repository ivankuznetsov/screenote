# frozen_string_literal: true

require "test_helper"

class OauthUserAuthenticationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @email = "oauth-cutover-#{SecureRandom.hex(6)}@example.test"
  end

  test "legacy signed-link generators are not exposed" do
    user = User.new

    assert_not_respond_to user, :generate_password_reset_token
    assert_not_respond_to user, :generate_magic_link_token
    assert_not_respond_to user, :generate_confirmation_token
  end

  teardown do
    User.where("email LIKE ?", "oauth-cutover-%@example.test").find_each(&:destroy!)
  end

  test "SaaS can create only a provider-verified identity" do
    unverified = google_auth(email: @email, uid: "google-unverified", verified: false)
    assert_nil User.authenticate_verified_oauth(unverified, allow_create: true)
    assert_nil User.find_by(email: @email)

    user = User.authenticate_verified_oauth(
      google_auth(email: @email.upcase, uid: "google-verified", verified: true),
      allow_create: true
    )

    assert user.persisted?
    assert_equal @email, user.email
    assert_equal "google_oauth2", user.oauth_provider
    assert_equal "google-verified", user.oauth_uid
    assert user.confirmed?
    identity = User.verified_oauth_identity(
      google_auth(email: @email, uid: "private-provider-uid", verified: true)
    )
    assert_not_includes identity.inspect, @email
    assert_not_includes identity.inspect, "private-provider-uid"
    assert_equal "[FILTERED]", identity.as_json
  end

  test "malformed provider identities fail closed before account lookup" do
    assert_nil User.verified_oauth_identity(nil)
    assert_nil User.verified_oauth_identity(
      google_auth(email: @email, uid: "uid", verified: true).merge("provider" => "unknown")
    )
    assert_nil User.verified_oauth_identity(
      google_auth(email: @email, uid: " ", verified: true)
    )
    assert_nil User.verified_oauth_identity(
      google_auth(email: "not-an-email", uid: "uid", verified: true)
    )
    assert_nil User.verified_oauth_identity(
      github_auth(email: @email, uid: "github-user", all_emails: nil)
    )
  end


  test "magic-link rate-limit identities are stable hashes without email PII" do
    first = MagicLinksController.rate_limit_identity(" #{@email.upcase} ")
    second = MagicLinksController.rate_limit_identity(@email)

    assert_equal first, second
    assert_match(/\A[0-9a-f]{64}\z/, first)
    assert_not_includes first, @email
  end

  test "GitHub requires a matching primary verified all_emails entry" do
    auth = github_auth(
      email: @email,
      uid: "github-user",
      all_emails: [ { "email" => @email, "primary" => false, "verified" => true } ]
    )
    assert_nil User.verified_oauth_identity(auth)

    auth["extra"]["all_emails"] = [
      { "email" => "other@example.test", "primary" => true, "verified" => true }
    ]
    assert_nil User.verified_oauth_identity(auth)

    auth["extra"]["all_emails"] = [
      { "email" => @email.upcase, "primary" => true, "verified" => true }
    ]
    assert_equal @email, User.verified_oauth_identity(auth).email
  end

  test "returning login requires exact provider uid and matching verified email" do
    user = User.create!(
      email: @email,
      password: "password123",
      confirmed_at: Time.current,
      oauth_provider: "google_oauth2",
      oauth_uid: "bound-uid"
    )

    assert_equal user,
      User.authenticate_verified_oauth(
        google_auth(email: @email, uid: "bound-uid", verified: true),
        allow_create: false
      )
    assert_nil User.authenticate_verified_oauth(
      google_auth(email: "different@example.test", uid: "bound-uid", verified: true),
      allow_create: false
    )
    assert_nil User.authenticate_verified_oauth(
      google_auth(email: @email, uid: "different-uid", verified: true),
      allow_create: false
    )

    user.update!(access_status: :suspended)
    assert_nil User.authenticate_verified_oauth(
      google_auth(email: @email, uid: "bound-uid", verified: true),
      allow_create: true
    )
  end

  test "an existing local email is never silently linked and self-hosted creation stays closed" do
    local = User.create!(email: @email, password: "password123", confirmed_at: Time.current)
    auth = google_auth(email: @email, uid: "unbound", verified: true)

    assert_nil User.authenticate_verified_oauth(auth, allow_create: true)
    assert_nil local.reload.oauth_provider

    local.destroy!
    assert_nil User.authenticate_verified_oauth(auth, allow_create: false)
    assert_nil User.find_by(email: @email)
  end

  test "a concurrent matching OAuth insert resolves to the locked active identity" do
    identity = User::OauthIdentity.new(
      provider: "google_oauth2",
      uid: "concurrent-provider-id",
      email: @email
    )
    existing = User.create!(
      email: @email,
      password: "password123",
      confirmed_at: Time.current,
      oauth_provider: identity.provider,
      oauth_uid: identity.uid
    )

    assert_equal existing, User.send(:create_verified_oauth_user, identity)
    assert_equal 1, User.where(email: @email).count
  end

  test "OAuth creation errors recover only an exact active identity" do
    identity = User::OauthIdentity.new(
      provider: "google_oauth2",
      uid: "retry-provider-id",
      email: @email
    )
    existing = User.create!(
      email: @email,
      password: "password123",
      confirmed_at: Time.current,
      oauth_provider: identity.provider,
      oauth_uid: identity.uid
    )
    exhausted = DatabaseRetry::Exhausted.new(ActiveRecord::Deadlocked.new, attempts: 3)

    with_singleton_method_stub(DatabaseRetry, :call, ->(*) { raise exhausted }) do
      assert_equal existing, User.send(:create_verified_oauth_user, identity)

      mismatched_email = identity.with(email: "different-#{@email}")
      assert_nil User.send(:create_verified_oauth_user, mismatched_email)

      absent_identity = identity.with(uid: "absent-provider-id")
      assert_nil User.send(:create_verified_oauth_user, absent_identity)

      existing.update!(access_status: :suspended)
      assert_nil User.send(:create_verified_oauth_user, identity)
    end
  end

  test "OAuth principal records reject an unknown authority kind" do
    token = Doorkeeper::AccessToken.new(
      application: create_oauth_application,
      resource_owner_id: users(:alice).id,
      scopes: "mcp_read",
      expires_in: 1.hour.to_i,
      principal_kind: "workspace"
    )

    assert_not token.valid?
    assert_includes token.errors[:principal_kind], "is not included in the list"
    assert_includes token.errors[:project_id], "must match the OAuth principal kind"
  end

  private

  def google_auth(email:, uid:, verified:)
    {
      "provider" => "google_oauth2",
      "uid" => uid,
      "info" => { "email" => email, "email_verified" => verified }
    }
  end

  def github_auth(email:, uid:, all_emails:)
    {
      "provider" => "github",
      "uid" => uid,
      "info" => { "email" => email },
      "extra" => { "all_emails" => all_emails }
    }
  end

  def with_singleton_method_stub(object, method_name, replacement)
    singleton = object.singleton_class
    original = object.method(method_name)
    singleton.define_method(method_name, replacement)
    yield
  ensure
    singleton&.define_method(method_name, original)
  end
end
