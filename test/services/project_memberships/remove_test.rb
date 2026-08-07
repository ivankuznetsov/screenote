# frozen_string_literal: true

require "test_helper"

module ProjectMemberships
  class RemoveTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    teardown do
      AuthenticationToken.delete_all
    end

    test "locks actor and target users before the project and removes the membership" do
      actor = users(:alice)
      target = users(:bob)
      project = projects(:alice_project)
      membership = project_memberships(:bob_member_of_alice_project)
      statements = []

      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        statements << payload.fetch(:sql)
      end
      result = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        Remove.call(project: project, membership_id: membership.id, actor: actor)
      end

      user_lock_indexes = statements.each_index.select do |index|
        statement = statements.fetch(index)
        if ActiveRecord::Base.connection.adapter_name.casecmp?("SQLite")
          statement.start_with?('UPDATE "users" SET')
        else
          statement.start_with?('SELECT "users".* FROM "users"') && statement.include?("FOR UPDATE")
        end
      end
      project_lock_index = statements.index do |statement|
        statement.start_with?('SELECT "projects".* FROM "projects"')
      end

      assert_equal 2, user_lock_indexes.length
      assert project_lock_index
      assert user_lock_indexes.all? { |index| index < project_lock_index }
      assert result.success?
      assert_equal membership.id, result.membership.id
      assert_not ProjectMembership.exists?(membership.id)
    end

    test "preserves forbidden, missing, and self-removal results" do
      actor = users(:alice)
      target = users(:bob)
      project = projects(:alice_project)
      target_membership = project_memberships(:bob_member_of_alice_project)
      actor_membership = project_memberships(:alice_owns_alice_project)

      forbidden = Remove.call(project: project, membership_id: actor_membership.id, actor: target)
      missing = Remove.call(project: project, membership_id: -1, actor: actor)
      self_removal = Remove.call(project: project, membership_id: actor_membership.id, actor: actor)

      assert_equal :forbidden, forbidden.status
      assert_equal :not_found, missing.status
      assert_equal :cannot_remove_self, self_removal.status
      assert ProjectMembership.exists?(target_membership.id)
      assert ProjectMembership.exists?(actor_membership.id)
    end

    test "removing an issuer cancels its prelocked invitations before project credentials" do
      actor = users(:alice)
      target = users(:bob)
      project = projects(:alice_project)
      membership = project_memberships(:bob_member_of_alice_project)
      membership.update!(role: :owner)
      invitation = project.project_invitations.create!(
        inviter: target,
        email: "removed-owner-invitee@example.test"
      )
      keyring = AuthenticationLinks::Keyring.new(
        secret_key_base: "membership-removal-invitation-test-secret-012345"
      )
      token = nil
      ProjectInvitation.transaction do
        locked = ProjectInvitation.lock.find(invitation.id)
        token = AuthenticationLinks::Issuer.new(
          origin: "https://screenote.example.test",
          keyring: keyring
        ).call(
          purpose: :invitation,
          subject: locked,
          expires_at: 7.days.from_now
        ).token
      end

      result = Remove.call(
        project: project,
        membership_id: membership.id,
        actor: actor
      )

      assert_equal :removed, result.status
      assert invitation.reload.cancelled?
      assert token.reload.cancelled?
    end

    test "returns retryable busy when the outer retry budget is exhausted" do
      original = DatabaseRetry.method(:call)
      DatabaseRetry.define_singleton_method(:call) do |**|
        error = SQLite3::BusyException.new("busy")
        raise DatabaseRetry::Exhausted.new(error, attempts: 3)
      end

      result = Remove.call(
        project: projects(:alice_project),
        membership_id: project_memberships(:bob_member_of_alice_project).id,
        actor: users(:alice)
      )

      assert_equal :retryable_busy, result.status
    ensure
      DatabaseRetry.define_singleton_method(:call, original)
    end

    test "fails closed for missing projects, actors, and suspended actors" do
      project = projects(:alice_project)
      membership = project_memberships(:bob_member_of_alice_project)

      assert_equal :forbidden,
        Remove.call(project: nil, membership_id: membership.id, actor: users(:alice)).status
      assert_equal :forbidden,
        Remove.call(project: project, membership_id: membership.id, actor: nil).status

      users(:alice).update!(access_status: :suspended)
      assert_equal :forbidden,
        Remove.call(project: project, membership_id: membership.id, actor: users(:alice)).status
      assert ProjectMembership.exists?(membership.id)
    end

    test "rejects a target identity that no longer matches the locked membership" do
      original = Remove.method(:target_user_for)
      mismatched_target = users(:unconfirmed)
      Remove.define_singleton_method(:target_user_for) { |**| mismatched_target }
      Remove.singleton_class.send(:private, :target_user_for)

      result = Remove.call(
        project: projects(:alice_project),
        membership_id: project_memberships(:bob_member_of_alice_project).id,
        actor: users(:alice)
      )

      assert_equal :not_found, result.status
    ensure
      Remove.define_singleton_method(:target_user_for, original)
      Remove.singleton_class.send(:private, :target_user_for)
    end

    test "does not revoke authority when membership destruction is rejected" do
      project = projects(:alice_project)
      membership = project_memberships(:bob_member_of_alice_project)
      token = create_oauth_token(
        application: create_oauth_application,
        user: users(:bob),
        project: project
      )
      original = ProjectMembership.instance_method(:destroy)
      ProjectMembership.define_method(:destroy) { false }

      result = Remove.call(project: project, membership_id: membership.id, actor: users(:alice))

      assert_equal :invalid, result.status
      assert ProjectMembership.exists?(membership.id)
      assert_not token.reload.revoked?
    ensure
      ProjectMembership.define_method(:destroy, original) if original
    end

    test "removal revokes only the target user's credentials bound to that project" do
      actor = users(:alice)
      target = users(:bob)
      project = projects(:alice_project)
      membership = project_memberships(:bob_member_of_alice_project)
      membership.update!(role: :owner)
      application = create_oauth_application(name: "Membership credential revocation")
      oauth_token = create_oauth_token(application: application, user: target, project: project)
      oauth_grant = Doorkeeper::AccessGrant.create!(
        application: application,
        resource_owner_id: target.id,
        token: SecureRandom.hex(32),
        expires_in: 10.minutes.to_i,
        redirect_uri: application.redirect_uri,
        scopes: "mcp_read",
        principal_kind: "project",
        project_id: project.id
      )
      device_grant = OauthDeviceGrant.create!(
        application: application,
        device_code: OauthDeviceGrant.digest_device_code(SecureRandom.urlsafe_base64(32)),
        user_code: SecureRandom.alphanumeric(10).insert(5, "-"),
        scopes: "mcp_read",
        expires_at: 10.minutes.from_now,
        resource_owner: target,
        project: project,
        principal_kind: "project",
        approved_at: Time.current
      )
      target_key = project.api_keys.create!(name: "Target owner key", issued_by_user: target)
      actor_key = api_keys(:alice_key)

      result = Remove.call(project: project, membership_id: membership.id, actor: actor)

      assert_equal :removed, result.status
      assert oauth_token.reload.revoked?
      assert oauth_grant.reload.revoked?
      assert_not OauthDeviceGrant.exists?(device_grant.id)
      assert target_key.reload.revoked?
      assert_not actor_key.reload.revoked?
    end
  end
end
