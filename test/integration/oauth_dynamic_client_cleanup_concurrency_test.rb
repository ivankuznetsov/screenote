# frozen_string_literal: true

require "test_helper"
require "timeout"

class OauthDynamicClientCleanupConcurrencyTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  REDIRECT_URI = "http://127.0.0.1:9877/callback"

  setup do
    require_postgresql!

    @application = Oauth::DynamicClientRegistration.call(
      client_name: "Cleanup race #{SecureRandom.hex(8)}",
      redirect_uris: [ REDIRECT_URI ]
    ).application
    @application.update_columns(created_at: 2.days.ago, last_used_at: nil)
    @session = ActionDispatch::Integration::Session.new(Rails.application)
    @session.post session_path, params: { email: users(:alice).email, password: "password123" }
    assert_equal 302, @session.response.status
    Rails.cache.clear
    Oauth::DeviceAuthorizationRateLimiter.reset!
  end

  teardown do
    return unless @application

    OauthDeviceGrant.where(application_id: @application.id).delete_all
    Doorkeeper::AccessGrant.where(application_id: @application.id).delete_all
    Doorkeeper::AccessToken.where(application_id: @application.id).delete_all
    @application.destroy! if @application.persisted?
    Rails.cache.clear
    Oauth::DeviceAuthorizationRateLimiter.reset!
  end

  test "cleanup waits for first authorization-code issuance and retains the client" do
    verifier = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

    response = assert_cleanup_waits_for(Doorkeeper::AccessGrant) do
      @session.post "/oauth/authorize", params: {
        client_id: @application.uid,
        redirect_uri: REDIRECT_URI,
        response_type: "code",
        scope: "mcp_read",
        code_challenge: challenge,
        code_challenge_method: "S256",
        state: "cleanup-race"
      }
      response_snapshot(@session)
    end

    assert_equal 302, response.fetch(:status)
    assert Doorkeeper::AccessGrant.where(application_id: @application.id).exists?
    assert @application.reload.last_used_at.present?
  end

  test "cleanup waits for first device grant issuance and retains the client" do
    session = ActionDispatch::Integration::Session.new(Rails.application)

    response = assert_cleanup_waits_for(OauthDeviceGrant) do
      session.post "/oauth/authorize_device", params: {
        client_id: @application.uid,
        scope: "mcp_read"
      }
      response_snapshot(session)
    end

    assert_equal 200, response.fetch(:status)
    assert OauthDeviceGrant.where(application_id: @application.id).exists?
    assert @application.reload.last_used_at.present?
  end

  private

  def assert_cleanup_waits_for(credential_model)
    entered_creation = Queue.new
    release_creation = Queue.new
    issuance_result = Queue.new
    cleanup_result = Queue.new
    singleton = credential_model.singleton_class
    original = credential_model.method(:create!)
    own_create = singleton.instance_method(:create!) if singleton.public_instance_methods(false).include?(:create!)

    singleton.define_method(:create!) do |*arguments, **keywords, &block|
      entered_creation << true
      release_creation.pop
      original.call(*arguments, **keywords, &block)
    end

    begin
      issuance = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { issuance_result << yield }
      rescue StandardError => error
        issuance_result << error
      end
      pop_with_timeout(entered_creation)

      cleanup = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          cleanup_result << Oauth::DynamicClientRegistration.cleanup_unused!(before: 1.day.ago)
        end
      rescue StandardError => error
        cleanup_result << error
      end

      assert_raises(Timeout::Error) { Timeout.timeout(0.2) { cleanup_result.pop } }
      release_creation << true
      join_with_timeout(issuance)
      join_with_timeout(cleanup)
    ensure
      release_creation << true if issuance&.alive?
      if own_create
        singleton.define_method(:create!, own_create)
      else
        singleton.remove_method(:create!)
      end
    end

    response = pop_with_timeout(issuance_result)
    cleanup_count = pop_with_timeout(cleanup_result)
    raise response if response.is_a?(Exception)
    raise cleanup_count if cleanup_count.is_a?(Exception)

    assert_equal 0, cleanup_count
    assert Doorkeeper::Application.exists?(@application.id)
    response
  end

  def response_snapshot(session)
    {
      status: session.response.status,
      location: session.response.location,
      body: session.response.parsed_body
    }
  end

  def pop_with_timeout(queue)
    Timeout.timeout(5) { queue.pop }
  end

  def join_with_timeout(thread)
    Timeout.timeout(5) { thread.join }
  end
end
