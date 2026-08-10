# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require_relative "../support/deterministic_concurrency_test_helper"

class BootstrapConcurrencyTest < ActiveSupport::TestCase
  include DeterministicConcurrencyTestHelper
  self.use_transactional_tests = false

  setup do
    suffix = SecureRandom.hex(8)
    @emails = [ "bootstrap-race-one-#{suffix}@example.test", "bootstrap-race-two-#{suffix}@example.test" ]
    InstallationAuditEvent.delete_all
    Installation.delete_all
    Installations::Prepare.call(deployment: self_hosted_deployment)
  end

  teardown do
    InstallationAuditEvent.delete_all
    Installation.delete_all
    User.where(email: @emails).delete_all
  end

  test "two independent database connections commit exactly one claim" do
    installation = Installation.current!
    claim = lambda do |email|
      Installations::Claim.call(
        email:,
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple",
        channel: "concurrency_test"
      )
    end

    outcomes = with_one_shot_instance_method_barrier(
      Installation,
      :update!,
      predicate: lambda do |record, attributes = {}, **keyword_attributes|
        attributes = keyword_attributes if attributes.empty?
        record.id == installation.id && attributes[:state] == "claimed"
      end
    ) do |entered, release|
      run_blocked_race(
        entered:,
        release:,
        first: -> { claim.call(@emails.first) },
        second: -> { claim.call(@emails.second) }
      )
    end

    assert_no_concurrency_exceptions(outcomes)
    assert_equal %i[claimed already_claimed], outcomes.map(&:status)
    assert_equal [ @emails.first ], User.where(email: @emails).pluck(:email)
    assert_equal 1, InstallationAuditEvent.where(event_type: "installation_claimed").count

    installation.reload
    assert installation.claimed?
    assert_equal @emails.first, installation.administrator.email
  end

  private

  def self_hosted_deployment
    @self_hosted_deployment ||= Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal",
        "SECRET_KEY_BASE" => "a" * 64
      },
      production: true
    )
  end
end
