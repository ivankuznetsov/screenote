# frozen_string_literal: true

class AdminMailer < ApplicationMailer
  def new_pro_subscriber(user)
    deployment = Screenote::Deployment.current
    return unless user && deployment.saas?

    @user = user
    mail to: deployment.saas_operator_email, subject: "New Pro subscriber: #{user.email}"
  end
end
