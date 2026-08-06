# frozen_string_literal: true

require "test_helper"

module Installations
  class PrepareTest < ActiveSupport::TestCase
    setup do
      InstallationAuditEvent.delete_all
      Installation.delete_all
    end

    test "retries one concurrent singleton creation loss and returns the durable winner" do
      attempts = 0
      original = Installation.method(:transaction)
      replacement = lambda do |**options, &block|
        attempts += 1
        raise ActiveRecord::RecordNotUnique, "concurrent singleton insert" if attempts == 1

        original.call(**options, &block)
      end

      with_singleton_method_stub(Installation, :transaction, replacement) do
        installation = Prepare.call(deployment: self_hosted_deployment)

        assert installation.persisted?
        assert installation.unclaimed?
      end

      assert_equal 2, attempts
      assert_equal 1, Installation.count
    end

    test "propagates a second singleton collision instead of retrying forever" do
      attempts = 0
      replacement = lambda do |**_options, &_block|
        attempts += 1
        raise ActiveRecord::RecordNotUnique, "persistent singleton collision"
      end

      error = with_singleton_method_stub(Installation, :transaction, replacement) do
        assert_raises(ActiveRecord::RecordNotUnique) do
          Prepare.call(deployment: self_hosted_deployment)
        end
      end

      assert_match(/persistent singleton collision/, error.message)
      assert_equal Prepare::MAX_CREATE_ATTEMPTS, attempts
      assert_equal 0, Installation.count
    end

    private

    def self_hosted_deployment
      Screenote::Deployment.new(
        {
          "SCREENOTE_EDITION" => "self_hosted",
          "SCREENOTE_BASE_URL" => "http://screenote.internal",
          "SECRET_KEY_BASE" => "a" * 64,
          "SCREENOTE_BOOTSTRAP_TOKEN" => "b" * 43
        },
        production: true
      )
    end

    def with_singleton_method_stub(object, method_name, replacement)
      singleton = object.singleton_class
      original = object.method(method_name)
      singleton.define_method(method_name, replacement)
      yield
    ensure
      singleton&.define_method(method_name, original)
    end
  end
end
