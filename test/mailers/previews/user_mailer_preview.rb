# frozen_string_literal: true

# Preview all emails at http://localhost:3005/rails/mailers/user_mailer
class UserMailerPreview < ActionMailer::Preview
  def confirmation
    UserMailer.confirmation(preview_user, "preview-confirmation-token-abc123")
  end

  def magic_link
    UserMailer.magic_link(preview_user, "preview-magic-link-token-xyz789")
  end

  def password_reset
    UserMailer.password_reset(preview_user, "preview-password-reset-token-def456")
  end

  private

  def preview_user
    User.first || User.new(email: "preview@screenote.app")
  end
end
