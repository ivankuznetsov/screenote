# frozen_string_literal: true

require "test_helper"

class InstallationAdministratorConstraintTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    InstallationAuditEvent.delete_all
    Installation.delete_all
    @administrator = User.create!(
      email: "constraint-administrator-#{SecureRandom.hex(8)}@example.test",
      password: "correct horse battery staple",
      confirmed_at: Time.current,
      access_status: :active
    )
    @installation = Installation.create!(
      singleton_key: Installation::SINGLETON_KEY,
      deployment_mode: "self_hosted",
      state: "claimed",
      storage_service: "self_hosted_local",
      storage_namespace_fingerprint: "f" * 64,
      administrator: @administrator,
      claimed_at: Time.current
    )
  end

  teardown do
    InstallationAuditEvent.delete_all
    Installation.delete_all
    User.where(id: @administrator&.id).delete_all
  end

  test "database foreign key prevents deleting the current administrator" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      User.where(id: @administrator.id).delete_all
    end

    assert_equal @administrator.id, @installation.reload.administrator_id
    assert @administrator.reload.active?
  end
end
