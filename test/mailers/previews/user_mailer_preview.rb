# frozen_string_literal: true

# Preview all emails at http://localhost:3005/rails/mailers/user_mailer
class UserMailerPreview < ActionMailer::Preview
  def confirmation
    user = User.first || User.new(email: "preview@screenote.app")
    UserMailer.confirmation(user, "preview-confirmation-token-abc123")
  end

  def magic_link
    user = User.first || User.new(email: "preview@screenote.app")
    UserMailer.magic_link(user, "preview-magic-link-token-xyz789")
  end

  def password_reset
    user = User.first || User.new(email: "preview@screenote.app")
    UserMailer.password_reset(user, "preview-password-reset-token-def456")
  end
end
