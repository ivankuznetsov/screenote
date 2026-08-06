# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class DatabaseConstraintContractTest < ActiveSupport::TestCase
  EXPECTED_CONSTRAINTS = {
    installations: %w[
      installations_deployment_mode installations_storage_service
      installations_valid_state
    ],
    users: %w[users_normalized_email users_valid_access_status users_valid_oauth_identity],
    project_invitations: %w[
      project_invitations_normalized_email project_invitations_valid_status
    ],
    api_keys: %w[api_keys_active_requires_issuer],
    annotations: %w[annotations_exactly_one_actor annotations_resolution_actor_state],
    oauth_access_tokens: %w[oauth_access_tokens_valid_principal oauth_access_tokens_hashed_token],
    authentication_tokens: %w[
      authentication_tokens_exact_subject authentication_tokens_recovery_issuer
      authentication_tokens_terminal_state
    ]
  }.freeze

  test "current schema exposes every named principal and state constraint" do
    EXPECTED_CONSTRAINTS.each do |table, expected|
      actual = connection.check_constraints(table).map(&:name)
      expected.each { |name| assert_includes actual, name, "missing #{table}.#{name}" }
    end
  end

  test "direct SQL cannot bypass installation identity actor or recovery invariants" do
    now = Time.current
    user = users(:alice)
    project = projects(:alice_project)
    screenshot = screenshots(:alice_screenshot)
    api_key = api_keys(:alice_key)

    assert_rejected do
      insert(:installations,
        singleton_key: "screenote", deployment_mode: "saas", state: "claimed",
        storage_service: "rabata", storage_namespace_fingerprint: "a" * 64,
        claimed_at: now, created_at: now, updated_at: now)
    end

    assert_rejected do
      insert(:users,
        email: " Mixed@Example.test ", password_digest: "digest", access_status: 0,
        created_at: now, updated_at: now)
    end

    assert_rejected do
      insert(:api_keys,
        project_id: project.id, issued_by_user_id: nil, name: "Unattributed active key",
        token_digest: Digest::SHA256.hexdigest("unattributed-active-key"),
        created_at: now, updated_at: now)
    end

    assert_rejected do
      insert(:annotations,
        screenshot_id: screenshot.id, user_id: nil, api_key_id: nil,
        comment: "No actor", x_percent: 1.0, y_percent: 1.0,
        status: 0, viewport: 0, created_at: now, updated_at: now)
    end

    assert_rejected do
      insert(:annotations,
        screenshot_id: screenshot.id, user_id: user.id, api_key_id: api_key.id,
        comment: "Two actors", x_percent: 2.0, y_percent: 2.0,
        status: 0, viewport: 0, created_at: now, updated_at: now)
    end

    assert_rejected do
      insert(:annotations,
        screenshot_id: screenshot.id, user_id: user.id,
        comment: "Resolved without resolver", x_percent: 3.0, y_percent: 3.0,
        status: 1, viewport: 0, created_at: now, updated_at: now)
    end

    assert_rejected do
      insert(:authentication_tokens,
        purpose: AuthenticationToken::PURPOSES.fetch(:account_recovery),
        user_id: user.id, issued_by_user_id: nil, generation: 91_001,
        derivation_id: Digest::SHA256.hexdigest("missing-recovery-issuer"),
        derivation_key_id: "v1.#{"a" * 43}",
        token_digest: Digest::SHA256.hexdigest("missing-recovery-token"),
        expires_at: now + 1.hour, state: 0, created_at: now, updated_at: now)
    end
  end

  test "direct SQL cannot widen OAuth principals or persist plaintext bearer tokens" do
    now = Time.current
    user = users(:alice)
    project = projects(:alice_project)
    application = Doorkeeper::Application.create!(
      name: "Invariant probe",
      redirect_uri: "http://127.0.0.1/callback",
      scopes: "mcp_read",
      confidential: false
    )

    assert_rejected do
      insert(:oauth_access_tokens,
        resource_owner_id: user.id, application_id: application.id,
        token: Digest::SHA256.hexdigest("invalid-principal-token"),
        previous_refresh_token: "", scopes: "mcp_read",
        principal_kind: "user", project_id: project.id, created_at: now)
    end

    assert_rejected do
      insert(:oauth_access_tokens,
        resource_owner_id: user.id, application_id: application.id,
        token: "raw-bearer-token", previous_refresh_token: "", scopes: "mcp_read",
        principal_kind: "user", project_id: nil, created_at: now)
    end
  end

  test "normalized pending invitations are unique at the database boundary" do
    now = Time.current
    project = projects(:alice_second_project)
    inviter = users(:alice)

    insert(:project_invitations,
      project_id: project.id, inviter_id: inviter.id, email: "pending@example.test",
      status: 0, created_at: now, updated_at: now)

    assert_rejected do
      insert(:project_invitations,
        project_id: project.id, inviter_id: inviter.id, email: "pending@example.test",
        status: 0, created_at: now, updated_at: now)
    end

    assert_rejected do
      insert(:project_invitations,
        project_id: project.id, inviter_id: inviter.id, email: " Pending@Example.test ",
        status: 1, created_at: now, updated_at: now)
    end
  end

  test "principal action table agrees with registered MCP tools and REST routes" do
    assert PrincipalActionContract.validate!

    registered_tools = Screenote::McpToolRegistry.tool_classes.map(&:tool_name)
    PrincipalActionContract::MCP_TOOLS.each_value do |tool_name|
      assert_includes registered_tools, tool_name
    end

    routes = Rails.application.routes.routes.map do |route|
      [ route.verb, route.path.spec.to_s ]
    end
    PrincipalActionContract::REST_ROUTES.each do |action, (verb, path)|
      assert routes.any? { |candidate_verb, candidate_path| candidate_verb == verb && path.match?(candidate_path) },
        "#{action} is declared for REST but no matching route exists"
    end

    assert_not PrincipalActionContract.supported?(:create_point, :rest)
    assert_not PrincipalActionContract.supported?(:create_area, :public_cli)
    assert PrincipalActionContract.supported?(:reopen, :mcp)
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  def insert(table, attributes)
    columns = attributes.keys.map { |column| connection.quote_column_name(column) }.join(", ")
    values = attributes.values.map { |value| connection.quote(value) }.join(", ")
    connection.execute(<<~SQL.squish)
      INSERT INTO #{connection.quote_table_name(table)} (#{columns}) VALUES (#{values})
    SQL
  end

  def assert_rejected(&block)
    assert_raises(ActiveRecord::StatementInvalid) do
      connection.transaction(requires_new: true, &block)
    end
  end
end
