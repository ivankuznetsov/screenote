# frozen_string_literal: true

require "test_helper"
require "timeout"

class OauthMembershipSerializationTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  REDIRECT_URI = "http://127.0.0.1:9876/callback"
  DEVICE_GRANT_TYPE = ScreenoteOauth::DeviceCodeGrant::GRANT_TYPE

  setup do
    suffix = SecureRandom.hex(6)
    @owner = create_user("oauth-owner-#{suffix}@example.test")
    @member = create_user("oauth-member-#{suffix}@example.test")
    @project = @owner.owned_projects.create!(name: "OAuth serialization #{suffix}")
    @membership = @project.project_memberships.create!(user: @member, role: :member)
    @application = create_oauth_application(name: "OAuth serialization #{suffix}", redirect_uri: REDIRECT_URI)
  end

  teardown do
    OauthDeviceGrant.where(application_id: @application&.id).delete_all
    Doorkeeper::AccessGrant.where(application_id: @application&.id).delete_all
    Doorkeeper::AccessToken.where(application_id: @application&.id).delete_all
    @application&.destroy! if @application&.persisted?
    @project&.destroy! if @project&.persisted?
    [ @member, @owner ].each { |user| user.destroy! if user&.persisted? }
  end

  test "project consent holds authority locks through authorization code creation" do
    session = signed_in_session(@member)
    _verifier, challenge = generate_pkce_challenge

    response = assert_removal_waits_for(Doorkeeper::AccessGrant) do
      session.post "/oauth/authorize", params: authorization_params(challenge: challenge)
      response_snapshot(session)
    end

    assert_equal 302, response.fetch(:status)
    code = Rack::Utils.parse_query(URI.parse(response.fetch(:location)).query).fetch("code")
    grant = Doorkeeper::AccessGrant.by_token(code)
    assert_equal @project.id, grant.project_id
    assert_not Oauth::PrincipalBinding.valid?(grant)
  end

  test "authorization code exchange holds authority locks through access token creation" do
    session = signed_in_session(@member)
    verifier, challenge = generate_pkce_challenge
    code = authorize_project(session, challenge: challenge)

    response = assert_removal_waits_for(Doorkeeper::AccessToken) do
      session.post "/oauth/token", params: {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: REDIRECT_URI,
        client_id: @application.uid,
        code_verifier: verifier
      }
      response_snapshot(session)
    end

    assert_equal 200, response.fetch(:status)
    token = Doorkeeper::AccessToken.by_token(response.fetch(:body).fetch("access_token"))
    assert_equal @project.id, token.project_id
    assert_not Oauth::PrincipalBinding.valid?(token)
  end

  test "refresh exchange holds authority locks through replacement token creation" do
    session = signed_in_session(@member)
    verifier, challenge = generate_pkce_challenge
    code = authorize_project(session, challenge: challenge)
    token_response = exchange_code(session, code: code, verifier: verifier)

    response = assert_removal_waits_for(Doorkeeper::AccessToken) do
      session.post "/oauth/token", params: {
        grant_type: "refresh_token",
        refresh_token: token_response.fetch("refresh_token"),
        client_id: @application.uid
      }
      response_snapshot(session)
    end

    assert_equal 200, response.fetch(:status)
    token = Doorkeeper::AccessToken.by_token(response.fetch(:body).fetch("access_token"))
    assert_equal @project.id, token.project_id
    assert_not Oauth::PrincipalBinding.valid?(token)
  end

  test "device exchange holds authority locks through access token creation" do
    device_code = SecureRandom.urlsafe_base64(32)
    OauthDeviceGrant.create!(
      application: @application,
      resource_owner: @member,
      project: @project,
      principal_kind: "project",
      device_code: OauthDeviceGrant.digest_device_code(device_code),
      user_code: unique_user_code,
      scopes: "mcp_read mcp_write",
      expires_at: OauthDeviceGrant::DEFAULT_EXPIRES_IN.seconds.from_now,
      approved_at: Time.current
    )
    session = ActionDispatch::Integration::Session.new(Rails.application)

    response = assert_removal_waits_for(Doorkeeper::AccessToken) do
      session.post "/oauth/token", params: {
        grant_type: DEVICE_GRANT_TYPE,
        device_code: device_code,
        client_id: @application.uid
      }
      response_snapshot(session)
    end

    assert_equal 200, response.fetch(:status)
    token = Doorkeeper::AccessToken.by_token(response.fetch(:body).fetch("access_token"))
    assert_equal @project.id, token.project_id
    assert_not Oauth::PrincipalBinding.valid?(token)
  end

  test "concurrent owners cannot remove each other and leave a project ownerless" do
    @membership.update!(role: :owner)
    owner_membership = @project.project_memberships.find_by!(user: @owner)
    start = Queue.new
    ready = Queue.new
    results = Queue.new

    threads = [
      [ @owner, @membership.id ],
      [ @member, owner_membership.id ]
    ].map do |actor, membership_id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          results << ProjectMemberships::Remove.call(
            project: Project.find(@project.id),
            membership_id: membership_id,
            actor: User.find(actor.id)
          )
        end
      rescue StandardError => error
        results << error
      end
    end

    2.times { pop_with_timeout(ready) }
    2.times { start << true }
    threads.each { |thread| join_with_timeout(thread) }
    outcomes = 2.times.map { pop_with_timeout(results) }

    assert outcomes.none?(Exception), -> { outcomes.grep(Exception).map(&:full_message).join("\n") }
    assert_equal [ :forbidden, :removed ], outcomes.map(&:status).sort
    assert_equal 1, @project.project_memberships.where(role: :owner).count
  end

  test "removing a member revokes every credential bound to that project authority" do
    @membership.update!(role: :owner)
    removed = create_project_credentials(@member)
    retained = create_project_credentials(@owner)

    result = ProjectMemberships::Remove.call(
      project: @project,
      membership_id: @membership.id,
      actor: @owner
    )

    assert result.success?
    assert removed.fetch(:grant).reload.revoked_at.present?
    assert removed.fetch(:token).reload.revoked_at.present?
    assert_not OauthDeviceGrant.exists?(removed.fetch(:device_grant).id)
    assert removed.fetch(:api_key).reload.revoked?

    assert_nil retained.fetch(:grant).reload.revoked_at
    assert_nil retained.fetch(:token).reload.revoked_at
    assert OauthDeviceGrant.exists?(retained.fetch(:device_grant).id)
    assert_not retained.fetch(:api_key).reload.revoked?
  end

  test "API key creation holds authority locks through insert and is revoked by a waiting removal" do
    @membership.update!(role: :owner)
    session = signed_in_session(@member)

    response = assert_removal_waits_for_api_key_save do
      session.post project_api_keys_path(@project), params: { api_key: { name: "Concurrent key" } }
      response_snapshot(session)
    end

    assert_equal 302, response.fetch(:status)
    key = @project.api_keys.find_by!(name: "Concurrent key")
    assert key.revoked?
    assert_not ProjectMembership.exists?(@membership.id)
  end

  private

  def create_user(email)
    User.create!(email: email, password: "password123", confirmed_at: Time.current)
  end

  def signed_in_session(user)
    ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.post session_path, params: { email: user.email, password: "password123" }
      assert_equal 302, session.response.status
    end
  end

  def authorization_params(challenge:)
    {
      client_id: @application.uid,
      redirect_uri: REDIRECT_URI,
      response_type: "code",
      scope: "mcp_read mcp_write",
      code_challenge: challenge,
      code_challenge_method: "S256",
      state: "serialization-state",
      principal_project_id: @project.id
    }
  end

  def authorize_project(session, challenge:)
    session.post "/oauth/authorize", params: authorization_params(challenge: challenge)
    assert_equal 302, session.response.status
    Rack::Utils.parse_query(URI.parse(session.response.location).query).fetch("code")
  end

  def exchange_code(session, code:, verifier:)
    session.post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: REDIRECT_URI,
      client_id: @application.uid,
      code_verifier: verifier
    }
    assert_equal 200, session.response.status
    session.response.parsed_body
  end

  def create_project_credentials(user)
    grant = Doorkeeper::AccessGrant.create!(
      application: @application,
      resource_owner_id: user.id,
      project_id: @project.id,
      principal_kind: "project",
      expires_in: 10.minutes.to_i,
      redirect_uri: REDIRECT_URI,
      scopes: "mcp_read"
    )
    token = create_oauth_token(
      application: @application,
      user: user,
      project: @project,
      scopes: "mcp_read mcp_write"
    )
    device_grant = OauthDeviceGrant.create!(
      application: @application,
      resource_owner: user,
      project: @project,
      principal_kind: "project",
      device_code: OauthDeviceGrant.digest_device_code(SecureRandom.urlsafe_base64(32)),
      user_code: unique_user_code,
      scopes: "mcp_read mcp_write",
      expires_at: OauthDeviceGrant::DEFAULT_EXPIRES_IN.seconds.from_now,
      approved_at: Time.current
    )
    api_key = @project.api_keys.create!(name: "#{user.email} key", issued_by_user: user)

    { grant: grant, token: token, device_grant: device_grant, api_key: api_key }
  end

  def response_snapshot(session)
    {
      status: session.response.status,
      location: session.response.location,
      body: session.response.parsed_body
    }
  end

  def assert_removal_waits_for(credential_model)
    entered_creation = Queue.new
    release_creation = Queue.new
    events = Queue.new
    issuance_result = Queue.new
    removal_result = Queue.new
    original_create = credential_model.method(:create!)
    singleton_class = credential_model.singleton_class
    own_create = singleton_class.instance_method(:create!) if singleton_class.public_instance_methods(false).include?(:create!)

    replacement = lambda do |*args, **kwargs, &block|
      entered_creation << true
      release_creation.pop
      original_create.call(*args, **kwargs, &block).tap { events << :credential_created }
    end

    singleton_class.define_method(:create!, &replacement)
    begin
      issuance = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          issuance_result << yield
        end
      rescue StandardError => error
        issuance_result << error
      end

      pop_with_timeout(entered_creation)
      removal = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          result = ProjectMemberships::Remove.call(
            project: Project.find(@project.id),
            membership_id: @membership.id,
            actor: User.find(@owner.id)
          )
          events << :membership_removed
          removal_result << result
        end
      rescue StandardError => error
        removal_result << error
      end

      assert_raises(Timeout::Error) { Timeout.timeout(0.2) { removal_result.pop } }
      release_creation << true
      join_with_timeout(issuance)
      join_with_timeout(removal)
    ensure
      release_creation << true if issuance&.alive?
      if own_create
        singleton_class.define_method(:create!, own_create)
      else
        singleton_class.remove_method(:create!)
      end
    end

    issuance = pop_with_timeout(issuance_result)
    removal = pop_with_timeout(removal_result)
    raise issuance if issuance.is_a?(Exception)
    raise removal if removal.is_a?(Exception)

    assert removal.success?, "expected membership removal to succeed, got #{removal.status.inspect}"
    assert_equal [ :credential_created, :membership_removed ], 2.times.map { pop_with_timeout(events) }
    issuance
  end

  def assert_removal_waits_for_api_key_save
    entered_save = Queue.new
    release_save = Queue.new
    events = Queue.new
    issuance_result = Queue.new
    removal_result = Queue.new
    original_save = ApiKey.instance_method(:save)
    own_save = ApiKey.instance_method(:save) if ApiKey.public_instance_methods(false).include?(:save)

    ApiKey.define_method(:save) do |*args, **kwargs, &block|
      entered_save << true
      release_save.pop
      original_save.bind_call(self, *args, **kwargs, &block).tap { events << :credential_created }
    end

    begin
      issuance = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          issuance_result << yield
        end
      rescue StandardError => error
        issuance_result << error
      end

      pop_with_timeout(entered_save)
      removal = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          result = ProjectMemberships::Remove.call(
            project: Project.find(@project.id),
            membership_id: @membership.id,
            actor: User.find(@owner.id)
          )
          events << :membership_removed
          removal_result << result
        end
      rescue StandardError => error
        removal_result << error
      end

      assert_raises(Timeout::Error) { Timeout.timeout(0.2) { removal_result.pop } }
      release_save << true
      join_with_timeout(issuance)
      join_with_timeout(removal)
    ensure
      release_save << true if issuance&.alive?
      if own_save
        ApiKey.define_method(:save, own_save)
      else
        ApiKey.remove_method(:save)
      end
    end

    issuance = pop_with_timeout(issuance_result)
    removal = pop_with_timeout(removal_result)
    raise issuance if issuance.is_a?(Exception)
    raise removal if removal.is_a?(Exception)

    assert removal.success?, "expected membership removal to succeed, got #{removal.status.inspect}"
    assert_equal [ :credential_created, :membership_removed ], 2.times.map { pop_with_timeout(events) }
    issuance
  end

  def unique_user_code
    raw = SecureRandom.alphanumeric(10).upcase
    "#{raw.first(5)}-#{raw.last(5)}"
  end

  def pop_with_timeout(queue)
    Timeout.timeout(5) { queue.pop }
  end

  def join_with_timeout(thread)
    Timeout.timeout(5) { thread.join }
  end
end
