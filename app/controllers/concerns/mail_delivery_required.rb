# frozen_string_literal: true

# Email-delivered authentication flows (password reset, magic links, email
# confirmation) do not exist on deployments without outbound mail.
module MailDeliveryRequired
  extend ActiveSupport::Concern

  included do
    before_action :require_mail
  end

  private

  def require_mail
    head :not_found unless Screenote::Deployment.current.mail?
  end
end
