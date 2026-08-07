# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require_relative "../support/deterministic_concurrency_test_helper"
require_relative "../support/instance_administration_test_helper"

class InstanceAdministrationConcurrencyTest < ActiveSupport::TestCase
  include DeterministicConcurrencyTestHelper
  include InstanceAdministrationTestHelper
  self.use_transactional_tests = false

  setup do
    @administrator = users(:alice)
    @first_target = users(:bob)
    @second_target = users(:admin)
    @installation = prepare_claimed_installation(administrator: @administrator)
    [ @first_target, @second_target ].each { |user| user.update!(access_status: :active) }
  end

  teardown do
    AuthenticationToken.delete_all
    InstallationAuditEvent.delete_all
    Installation.delete_all
  end

  test "two transfers on independent connections preserve one deterministic administrator" do
    outcomes = with_administrator_transfer_barrier(@first_target) do |entered, release|
      run_blocked_race(
        entered: entered,
        release: release,
        first: -> { Installations::TransferAdministrator.call(actor: @administrator, target: @first_target) },
        second: -> { Installations::TransferAdministrator.call(actor: @administrator, target: @second_target) }
      )
    end

    assert_no_concurrency_exceptions(outcomes)
    assert_equal %i[transferred stale_administrator], outcomes.map(&:status)
    assert_equal @first_target.id, @installation.reload.administrator_id
    assert @installation.administrator.active?
    assert_equal 1, Installation.where(singleton_key: Installation::SINGLETON_KEY).count
    assert_equal 1, InstallationAuditEvent.where(event_type: "administrator_transferred").count
  end

  test "concurrent recovery consumption has exactly one winner" do
    issued = create_recovery_token(subject: @first_target, issuer: @administrator)

    outcomes = with_recovery_consumption_barrier(issued.token) do |entered, release|
      run_blocked_race(
        entered: entered,
        release: release,
        first: -> { consume(issued.token.id, "first concurrent password") },
        second: -> { consume(issued.token.id, "second concurrent password") }
      )
    end

    assert_no_concurrency_exceptions(outcomes)
    assert_equal %i[recovered already_used], outcomes.map(&:status)
    assert issued.token.reload.consumed?
    assert_equal 1, InstallationAuditEvent.where(event_type: "account_recovered").count
    assert @first_target.reload.authenticate("first concurrent password")
    assert_not @first_target.authenticate("second concurrent password")
  end

  test "transfer racing target suspension leaves one active administrator" do
    outcomes = with_administrator_transfer_barrier(@first_target) do |entered, release|
      run_blocked_race(
        entered: entered,
        release: release,
        first: -> { Installations::TransferAdministrator.call(actor: @administrator, target: @first_target) },
        second: -> { InstanceAccounts::Suspend.call(actor: @administrator, target: @first_target) }
      )
    end

    assert_no_concurrency_exceptions(outcomes)
    assert_equal %i[transferred forbidden], outcomes.map(&:status)

    current_administrator = @installation.reload.administrator
    assert current_administrator.reload.active?
    assert_equal 1, Installation.where(singleton_key: Installation::SINGLETON_KEY).count
    assert_equal @first_target.id, current_administrator.id
    assert @first_target.active?
  end

  test "transfer racing recovery leaves no stale administrator credential" do
    issued = create_recovery_token(subject: @first_target, issuer: @administrator)

    outcomes = with_administrator_transfer_barrier(@second_target) do |entered, release|
      run_blocked_race(
        entered: entered,
        release: release,
        first: -> { Installations::TransferAdministrator.call(actor: @administrator, target: @second_target) },
        second: -> { consume(issued.token.id, "racing recovery password") }
      )
    end

    assert_no_concurrency_exceptions(outcomes)
    assert_equal %i[transferred issuer_revoked], outcomes.map(&:status)
    assert_equal @second_target, @installation.reload.administrator
    assert_includes %w[consumed cancelled], issued.token.reload.state

    replay = consume(issued.token.id, "stale recovery password")
    assert_equal :cancelled, replay.status
    assert_not @first_target.reload.authenticate("stale recovery password")
  end

  private

  def consume(token_id, password)
    AccountRecoveries::Consume.call(
      token_id: token_id,
      password: password,
      password_confirmation: password
    )
  end

  def with_administrator_transfer_barrier(target, &block)
    with_one_shot_instance_method_barrier(
      Installation,
      :update!,
      predicate: lambda do |record, attributes = {}, **keyword_attributes|
        attributes = keyword_attributes if attributes.empty?
        record.id == @installation.id && attributes[:administrator] == target
      end,
      &block
    )
  end

  def with_recovery_consumption_barrier(token, &block)
    with_one_shot_instance_method_barrier(
      AuthenticationToken,
      :transition_to!,
      predicate: ->(record, state, **) { record.id == token.id && state.to_sym == :consumed },
      &block
    )
  end
end
