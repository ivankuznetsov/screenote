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
    assert_includes html_body, "Screenote", "HTML body should contain the brand name"
    assert_includes html_body, "#e5a31e", "HTML body should use the gold accent color"
    assert_includes html_body, "#0a0a0f", "HTML body should use the dark background color"
  end

  test "confirmation email text body contains confirmation link" do
    email = UserMailer.confirmation(@user, "test-confirmation-token")
    text_body = email.text_part.body.to_s

    assert_includes text_body, "test-confirmation-token", "Text body should contain the confirmation token"
    assert_includes text_body, "Confirm your Screenote account", "Text body should contain the subject"
    assert_includes text_body, "24 hours", "Text body should mention expiry"
  end

  test "confirmation email is multipart" do
    email = UserMailer.confirmation(@user, "test-confirmation-token")
    assert email.multipart?, "Confirmation email should be multipart (HTML + text)"
    assert email.html_part.present?, "Should have an HTML part"
    assert email.text_part.present?, "Should have a text part"
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
    assert_includes html_body, "#e5a31e", "HTML body should use the gold accent color"
  end

  test "magic link email text body contains sign-in link" do
    email = UserMailer.magic_link(@user, "test-magic-token")
    text_body = email.text_part.body.to_s

    assert_includes text_body, "test-magic-token", "Text body should contain the magic link token"
    assert_includes text_body, "15 minutes", "Text body should mention expiry"
  end

  test "magic link email is multipart" do
    email = UserMailer.magic_link(@user, "test-magic-token")
    assert email.multipart?, "Magic link email should be multipart (HTML + text)"
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
    assert_includes html_body, "#e5a31e", "HTML body should use the gold accent color"
  end

  test "password reset email text body contains reset link" do
    email = UserMailer.password_reset(@user, "test-reset-token")
    text_body = email.text_part.body.to_s

    assert_includes text_body, "test-reset-token", "Text body should contain the reset token"
    assert_includes text_body, "15 minutes", "Text body should mention expiry"
    assert_includes text_body, "safely ignore", "Text body should have safety note"
  end

  test "password reset email is multipart" do
    email = UserMailer.password_reset(@user, "test-reset-token")
    assert email.multipart?, "Password reset email should be multipart (HTML + text)"
  end

  # --- Shared design consistency ---

  test "all emails use dark theme layout" do
    emails = [
      UserMailer.confirmation(@user, "token"),
      UserMailer.magic_link(@user, "token"),
      UserMailer.password_reset(@user, "token")
    ]

    emails.each do |email|
      html_body = email.html_part.body.to_s
      assert_includes html_body, "background-color: #0a0a0f", "Email should use dark background"
      assert_includes html_body, "background-color: #13131a", "Email should use dark surface card"
      assert_includes html_body, "Screenote", "Email should include brand name in footer"
      assert_includes html_body, "Visual feedback for AI agents", "Email should include tagline in footer"
    end
  end

  test "all emails have preheader text" do
    emails = {
      UserMailer.confirmation(@user, "token") => "Confirm your email",
      UserMailer.magic_link(@user, "token") => "sign-in link",
      UserMailer.password_reset(@user, "token") => "Reset your Screenote password"
    }

    emails.each do |email, expected_preheader|
      html_body = email.html_part.body.to_s
      assert_includes html_body, expected_preheader, "Email should have preheader containing '#{expected_preheader}'"
    end
  end

  test "all emails have fallback URL section" do
    emails = [
      UserMailer.confirmation(@user, "token"),
      UserMailer.magic_link(@user, "token"),
      UserMailer.password_reset(@user, "token")
    ]

    emails.each do |email|
      html_body = email.html_part.body.to_s
      assert_includes html_body, "Button not working?", "Email should have fallback URL section"
    end
  end
end
