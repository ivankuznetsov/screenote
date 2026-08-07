# frozen_string_literal: true

require "test_helper"

module InstanceAdministration
  class ResultTest < ActiveSupport::TestCase
    test "success recognizes only completed mutation statuses" do
      %i[issued recovered restored revoked suspended transferred].each do |status|
        assert Result.new(status: status).success?, status
      end

      %i[invalid forbidden unavailable retryable_busy].each do |status|
        assert_not Result.new(status: status).success?, status
      end
    end

    test "normalizes immutable errors and serializes optional identifiers" do
      user = users(:alice)
      token = Struct.new(:id).new(123)
      expires_at = 15.minutes.from_now
      result = Result.new(
        status: :issued,
        user: user,
        token: token,
        expires_at: expires_at,
        errors: { "email" => :invalid },
        details: { "generation" => 2 }
      )

      assert_equal [ "invalid" ], result.errors.fetch(:email)
      assert result.errors.frozen?
      assert result.errors.fetch(:email).frozen?
      assert result.details.frozen?
      assert_equal user.id, result.as_json.fetch("user_id")
      assert_equal token.id, result.as_json.fetch("token_id")
      assert_equal expires_at, result.as_json.fetch("expires_at")
      assert_equal [ "email" ], result.as_json.fetch("error_attributes")
      assert_match(/user_id=#{user.id}/, result.inspect)
      assert_match(/token_id=#{token.id}/, result.to_s)
    end

    test "failed result omits absent user and token identifiers" do
      result = Result.new(status: :unavailable)

      assert_not result.success?
      assert_match(/user_id=nil/, result.inspect)
      assert_match(/token_id=nil/, result.inspect)
      assert_nil result.as_json.fetch("user_id")
      assert_nil result.as_json.fetch("token_id")
      assert_empty result.errors
      assert_empty result.details
    end
  end
end
