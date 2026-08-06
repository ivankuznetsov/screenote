# frozen_string_literal: true

return unless ENV["SCREENOTE_PREPARE_CLAIMED_INSTALLATION"] == "1"

ActionDispatch::SystemTestCase.setup do
  deployment = Screenote::Deployment.current
  next unless deployment.self_hosted?

  InstallationAuditEvent.delete_all
  Installation.delete_all
  administrator = User.find_by!(email: "test@screenote.app")
  administrator.update!(access_status: :active)
  Installation.create!(
    singleton_key: Installation::SINGLETON_KEY,
    deployment_mode: "self_hosted",
    state: "claimed",
    storage_service: deployment.active_storage_service.to_s,
    storage_namespace_fingerprint: deployment.storage_namespace_fingerprint,
    administrator:,
    claimed_at: Time.current
  )
end
