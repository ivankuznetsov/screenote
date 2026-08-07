# frozen_string_literal: true

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module InstanceAccounts
  class SuspendTest < ActiveSupport::TestCase
    include InstanceAdministrationTestHelper
    self.use_transactional_tests = false

    BOB_API_KEY = "sk_proj_test_bob_key_0000000000000000000000000"

    setup do
      @administrator = users(:alice)
      @target = users(:bob)
      @installation = prepare_claimed_installation(administrator: @administrator)
      @target.update!(access_status: :active)
    end

    teardown do
      AuthenticationToken.delete_all
      InstallationAuditEvent.delete_all
      Installation.delete_all
    end

    test "suspends and atomically revokes every person-bound credential" do
      application = create_oauth_application(name: "Suspension test")
      oauth_token = create_oauth_token(application: application, user: @target)
      oauth_grant = Doorkeeper::AccessGrant.create!(
        application: application,
        resource_owner_id: @target.id,
        token: SecureRandom.hex(32),
        expires_in: 10.minutes.to_i,
        redirect_uri: application.redirect_uri,
        scopes: "mcp_read",
        principal_kind: "user"
      )
      device_grant = OauthDeviceGrant.create!(
        application: application,
        device_code: OauthDeviceGrant.digest_device_code(SecureRandom.urlsafe_base64(32)),
        user_code: SecureRandom.alphanumeric(10).insert(5, "-"),
        scopes: "mcp_read",
        expires_at: 10.minutes.from_now,
        resource_owner: @target,
        principal_kind: "user",
        approved_at: Time.current
      )
      recovery = create_recovery_token(subject: @target, issuer: @administrator)
      invitation = ProjectInvitation.create!(
        project: projects(:bob_project),
        inviter: @target,
        email: "suspend-invitee@example.test"
      )
      invitation_token = nil
      AuthenticationToken.transaction do
        AuthorityLock.users!(@target)
        project = Project.lock.find(invitation.project_id)
        invitation.lock!
        ProjectMembership.where(project: project).order(:id).lock.load
        invitation_token = AuthenticationLinks::Issuer.new(
          origin: "http://screenote.internal",
          keyring: AuthenticationLinks::Runtime.keyring
        ).call(purpose: :invitation, subject: invitation, expires_at: 1.day.from_now).token
      end


      assert Api::BearerAuthenticator.call(BOB_API_KEY)
      assert Api::BearerAuthenticator.call(oauth_token.token)

      assert_difference -> { InstallationAuditEvent.where(event_type: "account_suspended").count }, 1 do
        result = Suspend.call(actor: @administrator, target: @target)
        assert_equal :suspended, result.status
      end

      assert @target.reload.suspended?
      assert_empty @target.sessions.reload
      assert oauth_token.reload.revoked?
      assert oauth_grant.reload.revoked?
      assert_not OauthDeviceGrant.exists?(device_grant.id)
      assert api_keys(:bob_key).reload.revoked?
      assert_not api_keys(:alice_key).reload.revoked?
      assert invitation.reload.cancelled?
      assert invitation_token.reload.cancelled?
      assert recovery.token.reload.cancelled?
      assert_nil AuthenticatedPrincipal.for_user(@target)
      assert_nil Api::BearerAuthenticator.call(BOB_API_KEY)
      assert_nil Api::BearerAuthenticator.call(oauth_token.token)
    end

    test "cannot suspend the current administrator and audits the denial" do
      assert_no_changes -> { @administrator.reload.access_status } do
        assert_difference -> { InstallationAuditEvent.where(event_type: "instance_action_denied").count }, 1 do
          result = Suspend.call(actor: @administrator, target: @administrator)
          assert_equal :cannot_suspend_administrator, result.status
        end
      end
    end

    test "fails closed for unavailable, forbidden, and missing authority" do
      Installation.delete_all
      assert_equal :unavailable, Suspend.call(actor: @administrator, target: @target).status

      prepare_claimed_installation(administrator: @administrator)
      assert_equal :forbidden, Suspend.call(actor: @target, target: @target).status

      result = Suspend.call(actor: @administrator, target: nil)
      assert_equal :not_found, result.status
      event = InstallationAuditEvent.order(:id).last
      assert_equal "target_not_found", event.metadata.fetch("reason")
    end

    test "suspending an already suspended account is idempotent" do
      @target.update!(access_status: :suspended)

      assert_no_difference "InstallationAuditEvent.count" do
        result = Suspend.call(actor: @administrator, target: @target)
        assert_equal :already_suspended, result.status
        assert_equal @target, result.user
      end
    end

    test "maps retry exhaustion and database failures to stable statuses" do
      exhausted = DatabaseRetry::Exhausted.new(ActiveRecord::Deadlocked.new, attempts: 3)
      with_singleton_method_stub(DatabaseRetry, :call, ->(*) { raise exhausted }) do
        assert_equal :retryable_busy, Suspend.call(actor: @administrator, target: @target).status
      end

      with_singleton_method_stub(
        DatabaseRetry,
        :call,
        ->(*) { raise ActiveRecord::StatementInvalid, "database unavailable" }
      ) do
        assert_equal :unavailable, Suspend.call(actor: @administrator, target: @target).status
      end
    end

    test "audit failure rolls back suspension and credential revocation" do
      session_id = @target.sessions.first!.id
      invalid_event = InstallationAuditEvent.new
      invalid_event.errors.add(:metadata, "must be recorded")

      with_singleton_method_stub(
        InstallationAuditEvent,
        :create!,
        ->(**) { raise ActiveRecord::RecordInvalid.new(invalid_event) }
      ) do
        result = Suspend.call(actor: @administrator, target: @target)
        assert_equal :invalid, result.status
      end

      assert @target.reload.active?
      assert Session.exists?(session_id)
      assert api_keys(:bob_key).reload.revoked_at.nil?
    end
  end
end
