# frozen_string_literal: true

module InstanceAdministrationTestHelper
  def prepare_claimed_installation(administrator: users(:alice))
    InstallationAuditEvent.delete_all
    Installation.delete_all
    administrator.update!(access_status: :active)
    Installation.create!(
      singleton_key: Installation::SINGLETON_KEY,
      deployment_mode: "self_hosted",
      state: "claimed",
      storage_service: "self_hosted_local",
      storage_namespace_fingerprint: "f" * 64,
      administrator: administrator,
      claimed_at: Time.current
    )
  end

  def create_recovery_token(subject:, issuer:, now: Time.current, expires_at: now + 15.minutes)
    result = nil
    AuthenticationToken.transaction do
      AuthorityLock.users!(issuer, subject)
      link_issuer = AuthenticationLinks::Issuer.new(
        origin: "http://screenote.internal",
        keyring: AuthenticationLinks::Runtime.keyring,
        clock: -> { now }
      )
      result = link_issuer.call(
        purpose: :account_recovery,
        subject: subject,
        expires_at: expires_at,
        issued_by_user: issuer
      )
    end
    result
  end

  def with_singleton_method_stub(object, method_name, replacement)
    singleton = object.singleton_class
    original = object.method(method_name)
    singleton.define_method(method_name, replacement)
    yield
  ensure
    singleton&.define_method(method_name, original)
  end
end
