# frozen_string_literal: true

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module InstanceAdministration
  class AuthorityTest < ActiveSupport::TestCase
    include InstanceAdministrationTestHelper

    setup do
      @administrator = users(:alice)
      @target = users(:bob)
      @installation = prepare_claimed_installation(administrator: @administrator)
      @target.update!(access_status: :active)
    end

    test "missing installation returns an unavailable empty authority snapshot" do
      Installation.delete_all

      locked = Installation.transaction do
        Authority.lock(actor: @administrator, target: @target)
      end

      assert_nil locked.installation
      assert_nil locked.administrator
      assert_nil locked.actor
      assert_nil locked.target
      assert_not Authority.available?(locked)
      assert_not Authority.authorized?(locked)
    end

    test "locks and resolves administrator actor and target from durable ids" do
      locked = Installation.transaction do
        Authority.lock(actor: @administrator, target: @target)
      end

      assert_equal @installation, locked.installation
      assert_equal @administrator, locked.administrator
      assert_equal @administrator, locked.actor
      assert_equal @target, locked.target
      assert Authority.available?(locked)
      assert Authority.authorized?(locked)
      assert Authority.authorized?(locked, operator: true)
    end

    test "operator bypass applies only after installation availability is proven" do
      locked = Installation.transaction do
        Authority.lock(actor: nil, target: @target)
      end

      assert Authority.authorized?(locked, operator: true)
      assert_not Authority.authorized?(locked)

      unavailable = Authority::Locked.new(
        installation: @installation,
        administrator: nil,
        actor: nil,
        target: @target
      )
      assert_not Authority.available?(unavailable)
      assert_not Authority.authorized?(unavailable, operator: true)
    end

    test "active non-administrator and inactive administrator are unauthorized" do
      wrong_actor = Installation.transaction do
        Authority.lock(actor: @target, target: @administrator)
      end
      assert Authority.available?(wrong_actor)
      assert_not Authority.authorized?(wrong_actor)

      @administrator.update!(access_status: :suspended)
      inactive = Installation.transaction do
        Authority.lock(actor: @administrator, target: @target)
      end
      assert_not Authority.available?(inactive)
      assert_not Authority.authorized?(inactive)
    end
  end
end
