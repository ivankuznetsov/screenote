# frozen_string_literal: true

require "test_helper"

class AuthenticatedPrincipalTest < ActiveSupport::TestCase
  test "api keys produce an immutable project principal without impersonating the issuer" do
    api_key = api_keys(:alice_key)
    issuer = users(:alice)
    api_key.define_singleton_method(:issued_by_user) { issuer }

    principal = AuthenticatedPrincipal.for_api_key(api_key)

    assert_predicate principal, :frozen?
    assert_predicate principal, :project_principal?
    assert_predicate principal, :api_key?
    assert_nil principal.user
    assert_equal issuer, principal.issuer
    assert_equal projects(:alice_project), principal.project
    assert_equal %w[mcp_read mcp_write], principal.scopes
    assert principal.read?
    assert principal.write?
    assert principal.project_access?(projects(:alice_project))
    assert_not principal.project_access?(projects(:bob_project))
    assert_not principal.can_create_project?
    assert_not principal.can_invite_to?(projects(:alice_project))
    assert_raises(FrozenError) { principal.scopes << "extra" }
  end

  test "api key authentication rejects absent revoked and suspended issuer credentials" do
    assert_nil AuthenticatedPrincipal.for_api_key(nil)
    assert_nil AuthenticatedPrincipal.for_api_key(api_keys(:alice_key_revoked))

    users(:alice).update!(access_status: :suspended)
    assert_nil AuthenticatedPrincipal.for_api_key(api_keys(:alice_key))
  end

  test "user oauth preserves exact scopes and resolves only joined projects" do
    token = oauth_token_for(user: users(:alice), scopes: "mcp_read", principal_kind: "user")

    principal = AuthenticatedPrincipal.for_oauth_token(token)

    assert_predicate principal, :user_principal?
    assert_predicate principal, :oauth?
    assert_equal users(:alice), principal.user
    assert_equal users(:alice), principal.issuer
    assert_nil principal.project
    assert_equal [ "mcp_read" ], principal.scopes
    assert principal.read?
    assert_not principal.write?
    assert principal.project_access?(projects(:alice_project))
    assert_not principal.project_access?(projects(:bob_project))
    assert_not principal.can_create_project?
  end

  test "write-only project oauth stays bound and can invite only as its bound owner" do
    token = oauth_token_for(
      user: users(:alice),
      project: projects(:alice_project),
      scopes: "mcp_write",
      principal_kind: "project"
    )

    principal = AuthenticatedPrincipal.for_oauth_token(token)

    assert_predicate principal, :project_principal?
    assert_equal projects(:alice_project), principal.project
    assert_not principal.read?
    assert principal.write?
    assert_not principal.can_create_project?
    assert principal.can_invite_to?(projects(:alice_project))
    assert_not principal.can_invite_to?(projects(:bob_project))
  end

  test "project oauth is rejected when its user is not a current member" do
    token = oauth_token_for(
      user: users(:alice),
      project: projects(:bob_project),
      scopes: "mcp_read",
      principal_kind: "project"
    )

    assert_nil AuthenticatedPrincipal.for_oauth_token(token)
  end

  test "oauth principal kind and project binding must agree" do
    user_with_project = oauth_token_for(
      user: users(:alice),
      project: projects(:alice_project),
      scopes: "mcp_read",
      principal_kind: "user"
    )
    project_without_project = oauth_token_for(
      user: users(:alice),
      scopes: "mcp_read",
      principal_kind: "project"
    )

    assert_nil AuthenticatedPrincipal.for_oauth_token(user_with_project)
    assert_nil AuthenticatedPrincipal.for_oauth_token(project_without_project)
  end

  test "malformed OAuth credentials fail closed" do
    assert_nil AuthenticatedPrincipal.for_oauth_token(nil)

    token = oauth_token_for(user: users(:alice), scopes: "mcp_read", principal_kind: "user")
    token.define_singleton_method(:principal_kind) { nil }
    assert_nil AuthenticatedPrincipal.for_oauth_token(token)

    token.define_singleton_method(:principal_kind) { "workspace" }
    assert_nil AuthenticatedPrincipal.for_oauth_token(token)
  end

  test "browser users receive user authority with both core scopes" do
    principal = AuthenticatedPrincipal.for_user(users(:alice))

    assert_predicate principal, :user_principal?
    assert_predicate principal, :browser?
    assert principal.read?
    assert principal.write?
    assert principal.can_create_project?
  end

  test "project access rejects missing candidates and missing bound projects" do
    principal = AuthenticatedPrincipal.new(
      kind: :project,
      user: users(:alice),
      issuer: users(:alice),
      project: nil,
      scopes: "mcp_read mcp_write"
    )

    assert_equal %w[mcp_read mcp_write], principal.scopes
    assert_not principal.project_access?(nil)
    assert_not principal.project_access?(projects(:alice_project))
  end

  private

  def oauth_token_for(user:, scopes:, principal_kind:, project: nil)
    inferred_kind = project.present? ? "project" : "user"
    token = create_oauth_token(
      application: create_oauth_application,
      user: user,
      project: project,
      principal_kind: inferred_kind,
      scopes: scopes
    )
    token.define_singleton_method(:principal_kind) { principal_kind } if principal_kind != inferred_kind
    token
  end
end
