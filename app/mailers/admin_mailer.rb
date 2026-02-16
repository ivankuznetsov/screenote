# frozen_string_literal: true

class AdminMailer < ApplicationMailer
  ADMIN_EMAIL = "ivan@ikuznetsov.com"

  def new_pro_subscriber(user)
    @user = user
    mail to: ADMIN_EMAIL, subject: "New Pro subscriber: #{user.email}"
  end
end
