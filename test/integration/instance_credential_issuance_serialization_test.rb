# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "timeout"
require_relative "../support/instance_administration_test_helper"

class InstanceCredentialIssuanceSerializationTest < ActionDispatch::IntegrationTest
  include InstanceAdministrationTestHelper
  self.use_transactional_tests = false

  REDIRECT_URI = "http://127.0.0.1:9876/callback"

  setup do
    @administrator = users(:alice)
    @target = users(:bob)
    prepare_claimed_installation(administrator: @administrator)
    @target.update!(access_status: :active)
    @target.sessions.delete_all
    @application = create_oauth_application(name: "Instance suspension serialization", redirect_uri: REDIRECT_URI)
  end

  teardown do
    OauthDeviceGrant.where(application_id: @application&.id).delete_all
    Doorkeeper::AccessGrant.where(application_id: @application&.id).delete_all
    Doorkeeper::AccessToken.where(application_id: @application&.id).delete_all
    @application&.destroy! if @application&.persisted?
    AuthenticationToken.delete_all
    InstallationAuditEvent.delete_all
    Installation.delete_all
  end

  test "password sign in serializes session insert before suspension revocation" do
    response = with_instance_save_barrier(Session, :save!, ->(record, *) { record.user_id == @target.id && record.new_record? }) do
      browser = ActionDispatch::Integration::Session.new(Rails.application)
      browser.post session_path, params: { email: @target.email, password: "password123" }
      browser.response.status
    end

    assert_equal 302, response
    assert @target.reload.suspended?
    assert_empty @target.sessions

    assert_equal :restored, InstanceAccounts::Restore.call(actor: @administrator, target: @target).status
    assert_empty @target.sessions.reload
  end

  test "account OAuth consent serializes grant creation before suspension revocation" do
    browser = signed_in_session(@target)
    _verifier, challenge = generate_pkce_challenge

    response = with_class_create_barrier(Doorkeeper::AccessGrant) do
      browser.post "/oauth/authorize", params: {
        client_id: @application.uid,
        redirect_uri: REDIRECT_URI,
        response_type: "code",
        scope: "mcp_read",
        code_challenge: challenge,
        code_challenge_method: "S256",
        state: "suspension-race"
      }
      browser.response.status
    end

    assert_equal 302, response
    grant = Doorkeeper::AccessGrant.find_by!(application_id: @application.id, resource_owner_id: @target.id)
    assert grant.revoked?
  end

  test "account device approval serializes grant update before suspension revocation" do
    browser = signed_in_session(@target)
    grant = OauthDeviceGrant.create!(
      application: @application,
      device_code: OauthDeviceGrant.digest_device_code(SecureRandom.urlsafe_base64(32)),
      user_code: unique_user_code,
      scopes: "mcp_read",
      expires_at: OauthDeviceGrant::DEFAULT_EXPIRES_IN.seconds.from_now
    )

    response = with_instance_save_barrier(
      OauthDeviceGrant,
      :update!,
      ->(record, attributes = {}) { record.id == grant.id && attributes[:approved_at].present? }
    ) do
      browser.post "/oauth/device", params: {
        user_code: grant.user_code,
        decision: "approve"
      }
      browser.response.status
    end

    assert_equal 200, response
    assert_not OauthDeviceGrant.exists?(grant.id)
  end

  private

  def signed_in_session(user)
    ActionDispatch::Integration::Session.new(Rails.application).tap do |browser|
      browser.post session_path, params: { email: user.email, password: "password123" }
      assert_equal 302, browser.response.status
    end
  end

  def with_class_create_barrier(model, &issuance)
    singleton = model.singleton_class
    original = model.method(:create!)
    own_method = singleton.instance_method(:create!) if singleton.public_instance_methods(false).include?(:create!)

    with_suspension_barrier(
      install: ->(entered, release) do
        singleton.define_method(:create!) do |*args, **kwargs, &block|
          entered << true
          release.pop
          original.call(*args, **kwargs, &block)
        end
      end,
      restore: lambda do
        if own_method
          singleton.define_method(:create!, own_method)
        else
          singleton.remove_method(:create!)
        end
      end,
      &issuance
    )
  end

  def with_instance_save_barrier(model, method_name, predicate, &issuance)
    original = model.instance_method(method_name)
    own_method = model.instance_method(method_name) if model.public_instance_methods(false).include?(method_name)

    with_suspension_barrier(
      install: ->(entered, release) do
        model.define_method(method_name) do |*args, **kwargs, &block|
          if predicate.call(self, *args, **kwargs)
            entered << true
            release.pop
          end
          if method_name == :save! && args.one? && args.first.is_a?(Hash)
            original.bind_call(self, **args.first, **kwargs, &block)
          else
            original.bind_call(self, *args, **kwargs, &block)
          end
        end
      end,
      restore: lambda do
        if own_method
          model.define_method(method_name, own_method)
        else
          model.remove_method(method_name)
        end
      end,
      &issuance
    )
  end

  def with_suspension_barrier(install:, restore:)
    entered = Queue.new
    release = Queue.new
    issuance_result = Queue.new
    suspension_result = Queue.new
    install.call(entered, release)

    issuance = Thread.new do
      ApplicationRecord.connection_pool.with_connection { issuance_result << yield }
    rescue StandardError => error
      issuance_result << error
    end

    pop_with_timeout(entered)
    suspension = Thread.new do
      ApplicationRecord.connection_pool.with_connection do
        suspension_result << InstanceAccounts::Suspend.call(actor: @administrator, target: @target)
      end
    rescue StandardError => error
      suspension_result << error
    end

    assert_raises(Timeout::Error) { Timeout.timeout(0.2) { suspension_result.pop } }
    release << true
    join_with_timeout(issuance)
    join_with_timeout(suspension)

    issued = pop_with_timeout(issuance_result)
    suspended = pop_with_timeout(suspension_result)
    raise issued if issued.is_a?(Exception)
    raise suspended if suspended.is_a?(Exception)

    assert_equal :suspended, suspended.status
    issued
  ensure
    release << true if issuance&.alive?
    restore.call
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
