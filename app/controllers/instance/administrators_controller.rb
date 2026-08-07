# frozen_string_literal: true

module Instance
  class AdministratorsController < ApplicationController
    before_action :set_private_headers

    def transfer
      result = Installations::TransferAdministrator.call(
        actor: Current.user,
        target: User.find_by(id: params[:administrator_id])
      )

      case result.status
      when :transferred
        redirect_to dashboard_path, notice: "Instance administration transferred."
      when :already_administrator
        redirect_to instance_accounts_path, notice: "This account is already the administrator."
      when :target_inactive
        redirect_to instance_accounts_path, alert: "Restore the account before transferring administration."
      when :not_found
        redirect_to instance_accounts_path, alert: "Account no longer exists."
      when :stale_administrator, :forbidden
        redirect_to dashboard_path, alert: "Instance administration changed."
      when :retryable_busy
        redirect_to instance_accounts_path, alert: "Another administrator change is in progress. Please retry."
      else
        redirect_to instance_accounts_path, alert: "Administration could not be transferred."
      end
    end

    private

    def set_private_headers
      response.set_header("Cache-Control", "no-store, max-age=0")
      response.set_header("Pragma", "no-cache")
      response.set_header("Referrer-Policy", "no-referrer")
      response.set_header("X-Robots-Tag", "noindex, nofollow")
    end
  end
end
