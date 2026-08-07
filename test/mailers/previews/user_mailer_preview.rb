# frozen_string_literal: true

# Preview all emails at http://localhost:3005/rails/mailers/user_mailer
class UserMailerPreview < ActionMailer::Preview
  def confirmation
    preview_delivery(:email_confirmation, :confirmation)
  end

  def magic_link
    preview_delivery(:magic_link, :magic_link)
  end

  def password_reset
    preview_delivery(:password_reset, :password_reset)
  end

  def welcome
    UserMailer.welcome(preview_user)
  end

  private

  def preview_delivery(purpose, mailer_method)
    issued = nil
    AuthenticationToken.transaction do
      user = User.lock.find(preview_user.id)
      issued = AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring
      ).call(purpose:, subject: user, expires_at: 15.minutes.from_now)
    end
    UserMailer.public_send(mailer_method, preview_user.id, issued.token.id)
  end

  def preview_user
    User.first || User.create!(
      email: "preview@screenote.app",
      password: SecureRandom.hex(16),
      confirmed_at: Time.current
    )
  end
end
