# frozen_string_literal: true

require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:alice)
  end

  # --- Confirmation email ---

  test "confirmation email is sent to user" do
    email = UserMailer.confirmation(@user, "test-confirmation-token")
    assert_emails 1 do
      email.deliver_now
    end
  end

  test "confirmation email has correct headers" do
    email = UserMailer.confirmation(@user, "test-confirmation-token")
    assert_equal [ "alice@example.com" ], email.to
    assert_equal "Confirm your Screenote account", email.subject
    assert_equal [ ApplicationMailer.default[:from] ], email.from
  end

  test "confirmation email HTML body contains confirmation link" do
    email = UserMailer.confirmation(@user, "test-confirmation-token")
    html_body = email.html_part.body.to_s

    assert_includes html_body, "test-confirmation-token", "HTML body should contain the confirmation token"
    assert_includes html_body, "Confirm Email", "HTML body should contain the CTA text"
    assert_includes html_body, "Confirm your account", "HTML body should contain the title"
  end

  test "confirmation email text body contains confirmation link" do
    email = UserMailer.confirmation(@user, "test-confirmation-token")
    text_body = email.text_part.body.to_s

    assert_includes text_body, "test-confirmation-token", "Text body should contain the confirmation token"
    assert_includes text_body, "Confirm your Screenote account", "Text body should contain the heading"
    assert_includes text_body, "24 hours", "Text body should mention expiry"
  end

  # --- Magic link email ---

  test "magic link email is sent to user" do
    email = UserMailer.magic_link(@user, "test-magic-token")
    assert_emails 1 do
      email.deliver_now
    end
  end

  test "magic link email has correct headers" do
    email = UserMailer.magic_link(@user, "test-magic-token")
    assert_equal [ "alice@example.com" ], email.to
    assert_equal "Sign in to Screenote", email.subject
    assert_equal [ ApplicationMailer.default[:from] ], email.from
  end

  test "magic link email HTML body contains sign-in link" do
    email = UserMailer.magic_link(@user, "test-magic-token")
    html_body = email.html_part.body.to_s

    assert_includes html_body, "test-magic-token", "HTML body should contain the magic link token"
    assert_includes html_body, "Sign In", "HTML body should contain the CTA text"
    assert_includes html_body, "No password needed", "HTML body should contain the subtitle"
  end

  test "magic link email text body contains sign-in link" do
    email = UserMailer.magic_link(@user, "test-magic-token")
    text_body = email.text_part.body.to_s

    assert_includes text_body, "test-magic-token", "Text body should contain the magic link token"
    assert_includes text_body, "15 minutes", "Text body should mention expiry"
  end

  # --- Password reset email ---

  test "password reset email is sent to user" do
    email = UserMailer.password_reset(@user, "test-reset-token")
    assert_emails 1 do
      email.deliver_now
    end
  end

  test "password reset email has correct headers" do
    email = UserMailer.password_reset(@user, "test-reset-token")
    assert_equal [ "alice@example.com" ], email.to
    assert_equal "Reset your Screenote password", email.subject
    assert_equal [ ApplicationMailer.default[:from] ], email.from
  end

  test "password reset email HTML body contains reset link" do
    email = UserMailer.password_reset(@user, "test-reset-token")
    html_body = email.html_part.body.to_s

    assert_includes html_body, "test-reset-token", "HTML body should contain the reset token"
    assert_includes html_body, "Reset Password", "HTML body should contain the CTA text"
    assert_includes html_body, "Reset your password", "HTML body should contain the title"
  end

  test "password reset email text body contains reset link" do
    email = UserMailer.password_reset(@user, "test-reset-token")
    text_body = email.text_part.body.to_s

    assert_includes text_body, "test-reset-token", "Text body should contain the reset token"
    assert_includes text_body, "15 minutes", "Text body should mention expiry"
    assert_includes text_body, "safely ignore", "Text body should have safety note"
  end

  # --- Welcome email ---

  test "welcome email is sent to user" do
    email = UserMailer.welcome(@user)
    assert_emails 1 do
      email.deliver_now
    end
  end

  test "welcome email has correct headers" do
    email = UserMailer.welcome(@user)
    assert_equal [ "alice@example.com" ], email.to
    assert_equal "Welcome to Screenote", email.subject
    assert_equal [ ApplicationMailer.default[:from] ], email.from
  end

  test "welcome email HTML body contains getting started steps" do
    email = UserMailer.welcome(@user)
    html_body = email.html_part.body.to_s

    assert_includes html_body, "Welcome to Screenote", "HTML body should contain the title"
    assert_includes html_body, "Create a project", "HTML body should contain step 1"
    assert_includes html_body, "Upload screenshots", "HTML body should contain step 2"
    assert_includes html_body, "Annotate with feedback", "HTML body should contain step 3"
    assert_includes html_body, "Connect your AI agent", "HTML body should contain step 4"
    assert_includes html_body, "Go to Dashboard", "HTML body should contain the CTA text"
    assert_match %r{href="[^"]*dashboard"}, html_body, "HTML body should contain dashboard URL"
    assert_match %r{href="[^"]*help"}, html_body, "HTML body should contain help URL"
  end

  test "welcome email text body contains getting started steps" do
    email = UserMailer.welcome(@user)
    text_body = email.text_part.body.to_s

    assert_includes text_body, "Welcome to Screenote", "Text body should contain the heading"
    assert_includes text_body, "Create a project", "Text body should contain step 1"
    assert_includes text_body, "Upload screenshots", "Text body should contain step 2"
    assert_includes text_body, "Annotate with feedback", "Text body should contain step 3"
    assert_includes text_body, "Connect your AI agent", "Text body should contain step 4"
    assert_match %r{https?://.*dashboard}, text_body, "Text body should contain dashboard URL"
    assert_match %r{https?://.*help}, text_body, "Text body should contain help URL"
  end

  # --- Welcome email callback integration ---

  test "after_confirmation_callback sends welcome email on first confirmation" do
    user = users(:unconfirmed)
    callback = RailsSimpleAuth.configuration.after_confirmation_callback

    assert_nil user.confirmed_at, "Precondition: user should be unconfirmed"

    user.confirm!

    assert_enqueued_emails 1 do
      callback.call(user, nil)
    end
  end

  test "after_confirmation_callback does not send welcome email on reconfirmation" do
    user = users(:alice)
    callback = RailsSimpleAuth.configuration.after_confirmation_callback

    assert_not_nil user.confirmed_at, "Precondition: user should already be confirmed"

    assert_no_enqueued_emails do
      callback.call(user, nil)
    end
  end

  # --- Shared design consistency ---

  test "all emails are multipart with HTML and text parts" do
    all_emails.each do |email|
      assert email.multipart?, "#{email.subject} should be multipart (HTML + text)"
      assert email.html_part.present?, "#{email.subject} should have an HTML part"
      assert email.text_part.present?, "#{email.subject} should have a text part"
    end
  end

  test "all emails use dark theme layout" do
    all_emails.each do |email|
      html_body = email.html_part.body.to_s
      assert_includes html_body, "background-color: #0a0a0f", "Email should use dark background"
      assert_includes html_body, "background-color: #13131a", "Email should use dark surface card"
      assert_includes html_body, "#e5a31e", "Email should use the gold accent color"
      assert_includes html_body, "Screenote", "Email should include the brand name"
      assert_includes html_body, "Visual feedback for AI agents", "Email should include tagline in footer"
    end
  end

  test "all emails have preheader text" do
    emails = {
      UserMailer.confirmation(@user, "token") => "Confirm your email",
      UserMailer.magic_link(@user, "token") => "sign-in link",
      UserMailer.password_reset(@user, "token") => "Reset your Screenote password",
      UserMailer.welcome(@user) => "get started with Screenote"
    }

    emails.each do |email, expected_preheader|
      html_body = email.html_part.body.to_s
      assert_includes html_body, expected_preheader, "Email should have preheader containing '#{expected_preheader}'"
    end
  end

  test "all email CTA buttons link to correct URLs" do
    {
      UserMailer.confirmation(@user, "test-conf-token") => /href="[^"]*confirmation[^"]*test-conf-token/,
      UserMailer.magic_link(@user, "test-ml-token") => /href="[^"]*magic_link[^"]*test-ml-token/,
      UserMailer.password_reset(@user, "test-pr-token") => /href="[^"]*password[^"]*test-pr-token/
    }.each do |email, pattern|
      html_body = email.html_part.body.to_s
      assert_match pattern, html_body, "#{email.subject} CTA button href should contain the correct URL with token"
    end
  end

  test "all text emails contain full URLs with tokens" do
    {
      UserMailer.confirmation(@user, "test-conf-token") => %r{https?://.*test-conf-token},
      UserMailer.magic_link(@user, "test-ml-token") => %r{https?://.*test-ml-token},
      UserMailer.password_reset(@user, "test-pr-token") => %r{https?://.*test-pr-token}
    }.each do |email, pattern|
      text_body = email.text_part.body.to_s
      assert_match pattern, text_body, "#{email.subject} text body should contain a full URL with the token"
    end
  end

  test "token emails have fallback URL section" do
    token_emails = [
      UserMailer.confirmation(@user, "token"),
      UserMailer.magic_link(@user, "token"),
      UserMailer.password_reset(@user, "token")
    ]

    token_emails.each do |email|
      html_body = email.html_part.body.to_s
      assert_includes html_body, "Button not working?", "#{email.subject} should have fallback URL section"
    end
  end

  private

  def all_emails
    [
      UserMailer.confirmation(@user, "token"),
      UserMailer.magic_link(@user, "token"),
      UserMailer.password_reset(@user, "token"),
      UserMailer.welcome(@user)
    ]
  end
end
