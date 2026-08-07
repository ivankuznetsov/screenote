# frozen_string_literal: true

class UserMailer < ApplicationMailer
  def confirmation(user_id, token_id)
    load_authentication_link!(user_id, token_id, :email_confirmation)
    mail to: @user.email, subject: "Confirm your Screenote account"
  end

  def magic_link(user_id, token_id)
    load_authentication_link!(user_id, token_id, :magic_link)
    mail to: @user.email, subject: "Sign in to Screenote"
  end

  def password_reset(user_id, token_id)
    load_authentication_link!(user_id, token_id, :password_reset)
    mail to: @user.email, subject: "Reset your Screenote password"
  end

  def welcome(user)
    @user = user
    mail to: @user.email, subject: "Welcome to Screenote"
  end

  private

  def load_authentication_link!(user_id, token_id, expected_purpose)
    @user = User.find(Integer(user_id))
    token = AuthenticationToken.find(Integer(token_id))
    unless token.user_id == @user.id && token.purpose == expected_purpose.to_s
      raise ActiveRecord::RecordNotFound, "authentication link is unavailable"
    end

    presentation = AuthenticationLinks::Issuer.new(
      origin: AuthenticationLinks::Runtime.origin,
      keyring: AuthenticationLinks::Runtime.keyring
    ).re_present(token: token)
    @authentication_link_url = presentation.url
    @authentication_link_manual_code = presentation.manual_code
  end
end
