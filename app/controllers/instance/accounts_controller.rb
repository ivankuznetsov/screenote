# frozen_string_literal: true

module Instance
  class AccountsController < ApplicationController
    before_action :set_private_headers

    def index
      list_accounts
    end

    def suspend
      handle_mutation(InstanceAccounts::Suspend.call(actor: Current.user, target: target_user))
    end

    def restore
      handle_mutation(InstanceAccounts::Restore.call(actor: Current.user, target: target_user))
    end

    def revoke_credentials
      handle_mutation(InstanceAccounts::RevokeCredentials.call(actor: Current.user, target: target_user))
    end

    def issue_recovery
      unless request.format.turbo_stream?
        list_accounts
        return if performed?
      end

      result = InstanceAccounts::IssueRecovery.call(actor: Current.user, target: target_user)
      if result.status == :issued
        @recovery = result
        flash.now[:notice] = "Recovery link created. Copy it now; it will not be shown again."
        if request.format.turbo_stream?
          render :issue_recovery
        else
          render :index
        end
      else
        handle_mutation(result)
      end
    end

    private

    def target_user
      User.find_by(id: params[:id])
    end

    def list_accounts
      result = InstanceAccounts::List.call(actor: Current.user)
      if result.success?
        @accounts = result.accounts
        @administrator_id = result.administrator_id
      elsif result.status == :forbidden
        redirect_to dashboard_path, alert: "Not authorized."
      else
        response.set_header("Retry-After", "60")
        render plain: "Instance administration is temporarily unavailable.", status: :service_unavailable
      end
    end

    def handle_mutation(result)
      case result.status
      when :suspended
        redirect_to instance_accounts_path, notice: "Account suspended and credentials revoked."
      when :restored
        redirect_to instance_accounts_path, notice: "Account restored. New sign-in is required."
      when :revoked
        redirect_to instance_accounts_path, notice: "Account credentials revoked."
      when :already_suspended
        redirect_to instance_accounts_path, notice: "Account is already suspended."
      when :already_active
        redirect_to instance_accounts_path, notice: "Account is already active."
      when :cannot_suspend_administrator
        redirect_to instance_accounts_path,
          alert: "Transfer instance administration before suspending this account."
      when :not_found
        redirect_to instance_accounts_path, alert: "Account no longer exists."
      when :forbidden
        redirect_to dashboard_path, alert: "Not authorized."
      when :inactive_target
        redirect_to instance_accounts_path, alert: "Restore this account before issuing recovery."
      when :retryable_busy
        render_accounts_error("Another account change is in progress. Please retry.", status: :conflict)
      when :invalid
        render_accounts_error("The account change could not be completed.", status: :unprocessable_content)
      else
        render_accounts_unavailable
      end
    end

    def render_accounts_error(message, status:)
      list_accounts
      return if performed?

      response.set_header("Retry-After", "60") if status == :service_unavailable
      flash.now[:alert] = message
      render :index, formats: :html, status: status
    end

    def render_accounts_unavailable
      render_accounts_error(
        "Instance administration is temporarily unavailable.",
        status: :service_unavailable
      )
    end

    def set_private_headers
      response.set_header("Cache-Control", "no-store, max-age=0")
      response.set_header("Pragma", "no-cache")
      response.set_header("Referrer-Policy", "no-referrer")
      response.set_header("X-Robots-Tag", "noindex, nofollow")
    end
  end
end
