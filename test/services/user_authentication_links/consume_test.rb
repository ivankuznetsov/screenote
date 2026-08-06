# frozen_string_literal: true

require "test_helper"

module UserAuthenticationLinks
  class ConsumeTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    Deployment = Data.define(:mail?)

    setup do
      @user = User.create!(
        email: "consume-links-#{SecureRandom.hex(5)}@example.test",
        password: "password123",
        confirmed_at: Time.current
      )
      @user.sessions.create!(ip_address: "127.0.0.1", user_agent: "Test")
    end

    teardown do
      AuthenticationToken.where(user_id: @user&.id).delete_all
      @user&.destroy!
    end

    test "password reset changes credentials, revokes sessions, and has one winner" do
      issued = issue(:password_reset)
      assert @user.sessions.exists?

      result = Consume.call(
        token_id: issued.token.id,
        purpose: :password_reset,
        attributes: { password: "replacement-password", password_confirmation: "replacement-password" }
      )

      assert_equal :consumed, result.status
      assert @user.reload.authenticate("replacement-password")
      assert_empty @user.sessions.reload
      assert issued.token.reload.consumed?
      assert_equal :already_used,
        Consume.call(token_id: issued.token.id, purpose: :password_reset).status
    end

    test "invalid password leaves the link outstanding" do
      issued = issue(:password_reset)

      result = Consume.call(
        token_id: issued.token.id,
        purpose: :password_reset,
        attributes: { password: "short", password_confirmation: "different" }
      )

      assert_equal :validation_failed, result.status
      assert result.errors.key?(:password)
      assert issued.token.reload.outstanding?
    end

    test "missing password fields cannot consume a reset grant" do
      issued = issue(:password_reset)

      result = Consume.call(token_id: issued.token.id, purpose: :password_reset, attributes: {})

      assert_equal :validation_failed, result.status
      assert_equal [ "can't be blank" ], result.errors.fetch(:password)
      assert_equal [ "can't be blank" ], result.errors.fetch(:password_confirmation)
      assert issued.token.reload.outstanding?
    end

    test "magic link and confirmation confirm once and consume atomically" do
      @user.update!(confirmed_at: nil)
      magic = issue(:magic_link)

      result = Consume.call(token_id: magic.token.id, purpose: :magic_link)
      assert_equal :consumed, result.status
      assert result.newly_confirmed
      assert @user.reload.confirmed?
      assert magic.token.reload.consumed?

      @user.update!(confirmed_at: nil)
      confirmation = issue(:email_confirmation)
      result = Consume.call(token_id: confirmation.token.id, purpose: :email_confirmation)
      assert_equal :consumed, result.status
      assert result.newly_confirmed
      assert confirmation.token.reload.consumed?
    end

    test "suspended users cannot consume active links" do
      issued = issue(:magic_link)
      @user.update!(access_status: :suspended)

      result = Consume.call(token_id: issued.token.id, purpose: :magic_link)

      assert_equal :inactive_user, result.status
      assert issued.token.reload.outstanding?
    end

    test "reconfirmation is rejected and cancelled without mutating the target email" do
      issued = issue(:email_confirmation)
      original_email = @user.email

      result = Consume.call(
        token_id: issued.token.id,
        purpose: :email_confirmation,
        reconfirmation_checker: ->(_user) { true }
      )

      assert_equal :reconfirmation_unsupported, result.status
      assert_equal original_email, @user.reload.email
      assert issued.token.reload.cancelled?
    end

    private

    def issue(purpose)
      Issue.call(
        user: @user,
        purpose: purpose,
        deployment: Deployment.new(mail?: true),
        enqueue: false
      )
    end
  end
end
