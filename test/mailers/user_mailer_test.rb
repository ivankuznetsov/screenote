# frozen_string_literal: true

require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:alice)
  end

  test "credential emails reload integer ids and render fragment plus manual presentations" do
    {
      email_confirmation: [ :confirmation, "Confirm your Screenote account", "Confirm Email" ],
      magic_link: [ :magic_link, "Sign in to Screenote", "Sign In" ],
      password_reset: [ :password_reset, "Reset your Screenote password", "Reset Password" ]
    }.each do |purpose, (mailer_method, subject, label)|
      issued = issue(purpose)
      email = UserMailer.public_send(mailer_method, @user.id, issued.token.id)

      assert_equal [ @user.email ], email.to
      assert_equal subject, email.subject
      assert email.multipart?
      assert_includes email.html_part.body.to_s, issued.presentation.url
      assert_includes email.html_part.body.to_s, issued.presentation.manual_code
      assert_includes email.html_part.body.to_s, label
      assert_includes email.text_part.body.to_s, issued.presentation.url
      assert_includes email.text_part.body.to_s, issued.presentation.manual_code
      assert_match %r{/authentication-links/#{purpose}\#v1\.}, email.html_part.body.to_s
      assert_no_match %r{[?&](?:token|credential)=}, email.html_part.body.to_s
    end
  end

  test "credential mail cannot be rendered after terminalization or for a different user" do
    issued = issue(:password_reset)
    issued.token.transition_to!(:cancelled)

    assert_raises(AuthenticationLinks::Issuer::InvalidToken) do
      UserMailer.password_reset(@user.id, issued.token.id).message
    end

    issued = issue(:magic_link)
    assert_raises(ActiveRecord::RecordNotFound) do
      UserMailer.magic_link(users(:bob).id, issued.token.id).message
    end
  end

  test "welcome email keeps the branded multipart onboarding" do
    email = UserMailer.welcome(@user)

    assert_equal [ @user.email ], email.to
    assert_equal "Welcome to Screenote", email.subject
    assert email.multipart?
    assert_includes email.html_part.body.to_s, "Create a project"
    assert_includes email.html_part.body.to_s, "Install the Screenote CLI"
    assert_includes email.text_part.body.to_s, "Publish screenshots"
    assert_includes email.html_part.body.to_s, "background-color: #0a0a0f"
  end

  test "first confirmation still enqueues the welcome email" do
    user = users(:unconfirmed)
    user.confirm!

    assert_enqueued_emails 1 do
      RailsSimpleAuth.configuration.after_confirmation_callback.call(user, nil)
    end
  end

  private

  def issue(purpose)
    result = nil
    AuthenticationToken.transaction do
      user = User.lock.find(@user.id)
      result = AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring
      ).call(
        purpose: purpose,
        subject: user,
        expires_at: (purpose == :email_confirmation ? 24.hours : 15.minutes).from_now
      )
    end
    result
  end
end
