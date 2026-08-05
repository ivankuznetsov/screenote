# frozen_string_literal: true

require "test_helper"

class OauthDeviceConcurrencyTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  DEVICE_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code"

  setup do
    @user = users(:alice)
    @application = create_oauth_application(name: "Concurrent Device Client #{SecureRandom.hex(6)}")
    @application.update!(scopes: "mcp_read mcp_write")
    @device_code = SecureRandom.urlsafe_base64(32)
    @grant = OauthDeviceGrant.create!(
      application: @application,
      resource_owner: @user,
      device_code: OauthDeviceGrant.digest_device_code(@device_code),
      user_code: "C#{SecureRandom.alphanumeric(9).upcase.first(4)}-#{SecureRandom.alphanumeric(5).upcase}",
      scopes: "mcp_read mcp_write",
      expires_at: OauthDeviceGrant::DEFAULT_EXPIRES_IN.seconds.from_now,
      principal_kind: "user",
      approved_at: Time.current
    )
  end

  teardown do
    OauthDeviceGrant.where(application_id: @application.id).delete_all
    Doorkeeper::AccessToken.where(application_id: @application.id).delete_all
    @application.destroy!
  end

  test "concurrent final polls issue exactly one token without a server error" do
    ready = Queue.new
    start = Queue.new
    results = Queue.new

    threads = 2.times.map do
      Thread.new do
        session = ActionDispatch::Integration::Session.new(Rails.application)
        ready << true
        start.pop
        session.post "/oauth/token", params: token_params
        results << [ session.response.status, session.response.parsed_body ]
      rescue StandardError => error
        results << error
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)
    responses = 2.times.map { results.pop }

    assert responses.none?(Exception), -> { responses.grep(Exception).map(&:full_message).join("\n") }
    assert_equal [ 200, 400 ], responses.map(&:first).sort
    assert_equal [ "invalid_grant" ], responses.filter_map { |status, body| body["error"] if status == 400 }
    assert_equal 1, Doorkeeper::AccessToken.where(application_id: @application.id, resource_owner_id: @user.id).count
  end

  private

  def token_params
    {
      grant_type: DEVICE_GRANT_TYPE,
      device_code: @device_code,
      client_id: @application.uid
    }
  end
end
