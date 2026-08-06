# frozen_string_literal: true

namespace :screenote do
  namespace :instance do
    desc "Emit a single-use 15-minute recovery link for the current instance administrator"
    task recover_administrator: :environment do
      unless Screenote::Deployment.current.self_hosted?
        raise "Instance recovery is available only in self-hosted mode."
      end

      installation = Installation.current
      unless installation&.claimed? && installation.administrator
        raise "A claimed self-hosted installation is required."
      end

      result = InstanceAccounts::IssueRecovery.call(
        actor: nil,
        target: installation.administrator,
        operator: true,
        channel: "local_operator"
      )

      unless result.status == :issued
        raise "Administrator recovery could not be issued (#{result.status}). Retry the command."
      end

      puts result.presentation.url
    end

    desc "Transfer instance administration to an existing active account"
    task :transfer_administrator, [ :email ] => :environment do |_task, arguments|
      unless Screenote::Deployment.current.self_hosted?
        raise "Administrator transfer is available only in self-hosted mode."
      end

      normalized_email = AdmissionLock.normalize(arguments[:email])
      target = User.find_by(email: normalized_email)
      result = Installations::TransferAdministrator.call(
        actor: nil,
        target: target,
        operator: true,
        channel: "local_operator"
      )

      unless result.status == :transferred || result.status == :already_administrator
        raise "Administrator transfer failed (#{result.status}). No account was created."
      end

      puts "Instance administrator transferred to #{result.user.email}."
    end
  end
end
