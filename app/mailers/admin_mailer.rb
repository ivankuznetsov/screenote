# frozen_string_literal: true

class AdminMailer < ApplicationMailer
  def new_pro_subscriber(user)
    return unless user

    @user = user
    mail to: User::ADMIN_EMAIL, subject: "New Pro subscriber: #{user.email}"
  end
end
