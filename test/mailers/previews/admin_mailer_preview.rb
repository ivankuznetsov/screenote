# frozen_string_literal: true

# Preview all emails at http://localhost:3005/rails/mailers/admin_mailer
class AdminMailerPreview < ActionMailer::Preview
  def new_pro_subscriber
    AdminMailer.new_pro_subscriber(preview_user)
  end

  private

  def preview_user
    User.first || User.new(email: "preview@screenote.app")
  end
end
