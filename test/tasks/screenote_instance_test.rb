# frozen_string_literal: true

require "test_helper"
require "rake"
require_relative "../support/instance_administration_test_helper"

class ScreenoteInstanceTest < ActiveSupport::TestCase
  include InstanceAdministrationTestHelper
  self.use_transactional_tests = false

  setup do
    @deployment_current_method = Screenote::Deployment.method(:current)
    deployment = Screenote::Deployment.new({ "SCREENOTE_EDITION" => "self_hosted" })
    Screenote::Deployment.singleton_class.define_method(:current, -> { deployment })
    Rails.application.load_tasks unless Rake::Task.task_defined?("screenote:instance:recover_administrator")
    @administrator = users(:alice)
    @target = users(:bob)
    @installation = prepare_claimed_installation(administrator: @administrator)
    @target.update!(access_status: :active)
  end

  teardown do
    AuthenticationToken.delete_all
    InstallationAuditEvent.delete_all
    Installation.delete_all
  ensure
    Screenote::Deployment.singleton_class.define_method(:current, @deployment_current_method) if @deployment_current_method
  end

  test "recover administrator emits only one raw link and audits the local operator" do
    user_count = User.count

    stdout, stderr = capture_io { invoke_task("screenote:instance:recover_administrator") }

    assert_empty stderr
    assert_equal 1, stdout.lines.size
    assert_match %r{\A#{Regexp.escape(AuthenticationLinks::Runtime.origin)}/authentication-links/account_recovery#v1\.[A-Za-z0-9_-]{43}\n\z}, stdout
    assert_equal user_count, User.count

    token = AuthenticationToken.account_recovery.order(:id).last
    assert_equal @administrator, token.user
    assert_equal @administrator, token.issued_by_user
    assert token.outstanding?
    assert_in_delta 15.minutes, token.expires_at - token.created_at, 2.seconds

    event = InstallationAuditEvent.order(:id).last
    assert_equal "account_recovery_issued", event.event_type
    assert_nil event.actor_user
    assert_equal @administrator, event.target_user
    assert_equal "local_operator", event.metadata.fetch("channel")
    assert_not_includes event.attributes.to_json, stdout.strip.split("#", 2).last
  end

  test "transfer administrator accepts a normalized existing active account and creates no account" do
    user_count = User.count

    stdout, stderr = capture_io do
      invoke_task("screenote:instance:transfer_administrator", "  #{@target.email.upcase}  ")
    end

    assert_empty stderr
    assert_equal "Instance administrator transferred to #{@target.email}.\n", stdout
    assert_equal user_count, User.count
    assert_equal @target, @installation.reload.administrator

    event = InstallationAuditEvent.order(:id).last
    assert_equal "administrator_transferred", event.event_type
    assert_nil event.actor_user
    assert_equal "local_operator", event.metadata.fetch("channel")
  end

  test "transfer administrator rejects a missing or suspended account without mutation" do
    @target.update!(access_status: :suspended)

    assert_raises(RuntimeError) do
      capture_io { invoke_task("screenote:instance:transfer_administrator", @target.email) }
    end
    assert_equal @administrator, @installation.reload.administrator

    assert_raises(RuntimeError) do
      capture_io { invoke_task("screenote:instance:transfer_administrator", "missing@example.test") }
    end
    assert_equal @administrator, @installation.reload.administrator
  end

  private

  def invoke_task(name, *arguments)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*arguments)
  end
end
