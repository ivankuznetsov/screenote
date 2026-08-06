# frozen_string_literal: true

require "test_helper"

module Oauth
  class PrincipalBindingTest < ActiveSupport::TestCase
    Credential = Struct.new(:resource_owner_id, :principal_kind, :project_id, keyword_init: true) do
      def lock!
        self
      end
    end

    test "validates only active users and authority shapes they still hold" do
      user = users(:alice)
      project = projects(:alice_project)

      assert_not PrincipalBinding.valid?(nil)
      assert PrincipalBinding.valid?(credential(user: user, principal_kind: "user"))
      assert_not PrincipalBinding.valid?(
        credential(user: user, principal_kind: "user", project: project)
      )
      assert PrincipalBinding.valid?(
        credential(user: user, principal_kind: "project", project: project)
      )
      assert_not PrincipalBinding.valid?(
        credential(user: user, principal_kind: "project", project: projects(:bob_project))
      )
      assert_not PrincipalBinding.valid?(credential(user: user, principal_kind: "workspace"))

      user.update!(access_status: :suspended)
      assert_not PrincipalBinding.valid?(credential(user: user, principal_kind: "user"))
    end

    test "locks account credentials after the resource owner and reports current validity" do
      user = users(:alice)
      token = create_oauth_token(application: create_oauth_application, user: user)
      yielded = nil

      PrincipalBinding.with_locked_credential(token) { |valid| yielded = valid }
      assert_equal true, yielded

      user.update!(access_status: :suspended)
      PrincipalBinding.with_locked_credential(token) { |valid| yielded = valid }
      assert_equal false, yielded
    end

    test "locks project membership and rejects stale project authority" do
      user = users(:bob)
      project = projects(:alice_project)
      token = create_oauth_token(
        application: create_oauth_application,
        user: user,
        project: project
      )

      PrincipalBinding.with_locked_credential(token) do |valid|
        assert valid
      end

      project.project_memberships.find_by!(user: user).delete
      PrincipalBinding.with_locked_credential(token) do |valid|
        assert_not valid
      end
    end

    test "unknown and absent credential shapes are locked defensively and rejected" do
      unknown = credential(user: users(:alice), principal_kind: "workspace")
      yielded = nil

      PrincipalBinding.with_locked_credential(unknown) { |valid| yielded = valid }
      assert_equal false, yielded

      PrincipalBinding.with_locked_credential(nil) { |valid| yielded = valid }
      assert_equal false, yielded
    end

    test "missing authority and credential rows fail closed during lock acquisition" do
      user = User.create!(email: "principal-lock-race@example.test", password: "password123")
      token = create_oauth_token(application: create_oauth_application, user: user)
      user.delete

      PrincipalBinding.with_locked_user(user: user) do |valid, locked_user|
        assert_not valid
        assert_nil locked_user
      end

      live_user = users(:alice)
      deleted_token = create_oauth_token(application: create_oauth_application, user: live_user)
      deleted_token.delete
      deleted_token.define_singleton_method(:lock!) { raise ActiveRecord::RecordNotFound }
      PrincipalBinding.with_locked_user(user: live_user, credential: deleted_token) do |valid, locked_user|
        assert_not valid
        assert_equal live_user, locked_user
      end
    end

    test "project selection fails closed when either authority row is absent" do
      user = users(:alice)

      PrincipalBinding.with_locked_project(user: nil, project_id: projects(:alice_project).id) do |valid, membership|
        assert_not valid
        assert_nil membership
      end
      PrincipalBinding.with_locked_project(user: user, project_id: -1) do |valid, membership|
        assert_not valid
        assert_nil membership
      end
    end

    private

    def credential(user:, principal_kind:, project: nil)
      Credential.new(resource_owner_id: user.id, principal_kind: principal_kind, project_id: project&.id)
    end
  end
end
