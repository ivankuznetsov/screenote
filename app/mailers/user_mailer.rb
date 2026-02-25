# frozen_string_literal: true

class UserMailer < ApplicationMailer
  def confirmation(user, confirmation_token)
    @user = user
    @confirmation_token = confirmation_token
    mail to: @user.email, subject: "Confirm your Screenote account"
  end

  def magic_link(user, token)
    @user = user
    @token = token
    mail to: @user.email, subject: "Sign in to Screenote"
  end

  def password_reset(user, password_reset_token)
    @user = user
    @password_reset_token = password_reset_token
    mail to: @user.email, subject: "Reset your Screenote password"
  end

  def welcome(user)
    @user = user
    mail to: @user.email, subject: "Welcome to Screenote"
  end
end
