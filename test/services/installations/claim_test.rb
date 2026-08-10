# frozen_string_literal: true

require "test_helper"

module Installations
  class ClaimTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    CLAIM_EMAIL = "bootstrap-admin@example.test"
    VALID_PASSWORD = "correct horse battery staple"

    setup do
      clean_claim_records
      @installation = Prepare.call(deployment: self_hosted_deployment)
    end

    teardown do
      clean_claim_records
    end

    test "claims an unclaimed installation and appends one redacted audit event" do
      result = claim

      assert_equal :claimed, result.status
      assert result.claimed?
      assert_equal CLAIM_EMAIL, result.user.email
      assert result.user.confirmed?
      assert result.user.active?
      assert_empty result.errors

      @installation.reload
      assert @installation.claimed?
      assert_equal result.user, @installation.administrator
      assert @installation.claimed_at

      event = InstallationAuditEvent.find_by!(installation: @installation)
      assert_equal "installation_claimed", event.event_type
      assert_equal result.user, event.actor_user
      assert_equal result.user, event.target_user
      assert_equal({ "channel" => "web" }, event.metadata)
      assert_no_match VALID_PASSWORD, event.attributes.to_json
      assert_no_match VALID_PASSWORD, result.inspect
      assert_no_match VALID_PASSWORD, result.as_json.to_json
    end

    test "operation inspection never exposes submitted credentials" do
      operation = Claim.new(
        email: CLAIM_EMAIL,
        password: VALID_PASSWORD,
        password_confirmation: VALID_PASSWORD,
        channel: "web"
      )

      assert_no_match VALID_PASSWORD, operation.inspect
      assert_no_match CLAIM_EMAIL, operation.inspect
      assert_equal operation.inspect, operation.to_s
      assert_no_match VALID_PASSWORD, operation.as_json.to_json
      assert_no_match CLAIM_EMAIL, operation.as_json.to_json
    end

    test "invalid administrator form rolls back and leaves setup available" do
      assert_no_difference [ "User.count", "InstallationAuditEvent.count" ] do
        result = claim(password: "short", password_confirmation: "different")

        assert_equal :invalid, result.status
        assert_nil result.user
        assert result.errors.key?(:password)
      end

      assert @installation.reload.unclaimed?
      assert_equal :claimed, claim.status
    end

    test "audit failure rolls back the user and leaves setup available" do
      invalid_event = InstallationAuditEvent.new
      invalid_event.errors.add(:metadata, "must be recorded")

      assert_no_difference [ "User.count", "InstallationAuditEvent.count" ] do
        with_singleton_method_stub(
          InstallationAuditEvent,
          :create!,
          ->(**) { raise ActiveRecord::RecordInvalid.new(invalid_event) }
        ) do
          result = claim

          assert_equal :invalid, result.status
          assert_nil result.user
          assert_equal [ "must be recorded" ], result.errors.fetch(:metadata)
        end
      end

      assert @installation.reload.unclaimed?
      assert_equal :claimed, claim.status
    end

    test "existing normalized email is rejected without claiming the installation" do
      existing_user = users(:alice)

      assert_no_difference [ "User.count", "InstallationAuditEvent.count" ] do
        result = claim(email: "  #{existing_user.email.upcase}  ")

        assert_equal :email_taken, result.status
        assert_nil result.user
      end

      assert @installation.reload.unclaimed?
    end

    test "blank normalized email is invalid without claiming the installation" do
      assert_no_difference [ "User.count", "InstallationAuditEvent.count" ] do
        result = claim(email: "  ")

        assert_equal :invalid, result.status
        assert_equal [ "can't be blank" ], result.errors.fetch(:email)
      end

      assert @installation.reload.unclaimed?
    end

    test "constraint specific email collision maps to email taken after rollback" do
      collision = ActiveRecord::RecordNotUnique.new(
        "duplicate key violates index_users_on_normalized_email"
      )

      with_singleton_method_stub(User, :create!, ->(**) { raise collision }) do
        with_singleton_method_stub(User, :exists?, ->(*) { true }) do
          result = claim

          assert_equal :email_taken, result.status
          assert_nil result.user
          assert_equal [ "has already been taken" ], result.errors.fetch(:email)
        end
      end

      assert @installation.reload.unclaimed?
    end

    test "an unrelated uniqueness failure is unavailable rather than misreported as email taken" do
      collision = ActiveRecord::RecordNotUnique.new("duplicate key violates unrelated_index")

      with_singleton_method_stub(User, :create!, ->(**) { raise collision }) do
        result = claim

        assert_equal :unavailable, result.status
        assert_nil result.user
        assert_empty result.errors
      end

      assert @installation.reload.unclaimed?
    end

    test "a repeated claim returns already claimed without returning the administrator" do
      assert_equal :claimed, claim.status

      assert_no_difference [ "User.count", "InstallationAuditEvent.count" ] do
        result = claim

        assert_equal :already_claimed, result.status
        assert_nil result.user
        assert_empty result.errors
        assert_equal result.inspect, result.to_s
        assert_equal "already_claimed", result.as_json.fetch("status")
        assert_nil result.as_json.fetch("user_id")
      end
    end

    test "invalid audit channel is normalized without reflecting submitted text" do
      submitted_channel = " WEB/../../private "

      result = claim(channel: submitted_channel)

      assert_equal :claimed, result.status
      event = InstallationAuditEvent.find_by!(installation: @installation)
      assert_equal "unknown", event.metadata.fetch("channel")
      assert_not_includes event.attributes.to_json, submitted_channel
    end

    test "unexpected argument errors are not mistaken for blank email" do
      with_singleton_method_stub(AdmissionLock, :email!, ->(*) { raise ArgumentError, "normalizer failed" }) do
        error = assert_raises(ArgumentError) { claim }
        assert_equal "normalizer failed", error.message
      end

      assert @installation.reload.unclaimed?
    end

    test "generic persistence failure returns unavailable and rolls back" do
      with_singleton_method_stub(
        User,
        :create!,
        ->(**) { raise ActiveRecord::StatementInvalid, "database unavailable" }
      ) do
        result = claim

        assert_equal :unavailable, result.status
        assert_nil result.user
        assert_empty result.errors
      end

      assert @installation.reload.unclaimed?
      assert_equal 0, InstallationAuditEvent.count
    end

    test "uniqueness failure before email normalization fails closed as unavailable" do
      collision = ActiveRecord::RecordNotUnique.new("duplicate admission lock")

      with_singleton_method_stub(AdmissionLock, :email!, ->(*) { raise collision }) do
        result = claim

        assert_equal :unavailable, result.status
        assert_nil result.user
      end

      assert @installation.reload.unclaimed?
    end

    test "record invalid without an errors interface remains a safe invalid result" do
      invalid = ActiveRecord::RecordInvalid.allocate
      invalid.instance_variable_set(:@record, Object.new)

      with_singleton_method_stub(User, :create!, ->(**) { raise invalid }) do
        result = claim

        assert_equal :invalid, result.status
        assert_empty result.errors
      end

      assert @installation.reload.unclaimed?
    end

    test "missing SaaS and malformed installation state are unavailable" do
      Installation.delete_all
      assert_equal :unavailable, claim.status

      Prepare.call(deployment: saas_deployment)
      assert_equal :unavailable, claim.status

      malformed = Installation.new(
        singleton_key: Installation::SINGLETON_KEY,
        deployment_mode: "self_hosted",
        state: "claimed",
        storage_service: "self_hosted_local",
        storage_namespace_fingerprint: "f" * 64
      )
      relation = Object.new
      relation.define_singleton_method(:find_by) { |**| malformed }
      with_singleton_method_stub(Installation, :lock, -> { relation }) do
        assert_equal :unavailable, claim.status
      end
    end

    test "exhausted database contention returns retryable busy" do
      error = DatabaseRetry::Exhausted.new(StandardError.new("busy"), attempts: 3)

      with_singleton_method_stub(DatabaseRetry, :call, ->(**, &) { raise error }) do
        result = claim

        assert_equal :retryable_busy, result.status
        assert_nil result.user
        assert_empty result.errors
      end
    end

    test "self hosted development seeds create no users or projects" do
      with_current_deployment(self_hosted_deployment) do
        with_singleton_method_stub(Rails.env, :development?, -> { true }) do
          output = nil
          assert_no_difference [ "User.count", "Project.count" ] do
            output, = capture_io { load Rails.root.join("db/seeds.rb") }
          end
          assert_match "starts with zero accounts", output
        end
      end
    end

    test "SaaS development seeds remain available" do
      subscription = users(:test_user).subscription
      original_subscription_attributes = subscription.attributes.slice(
        "stripe_subscription_id",
        "plan",
        "status",
        "current_period_end"
      )

      with_current_deployment(saas_deployment) do
        with_singleton_method_stub(Rails.env, :development?, -> { true }) do
          output, = capture_io { load Rails.root.join("db/seeds.rb") }
          assert_match "Seed data created", output
        end
      end

      test_user = User.find_by!(email: "test@screenote.app")
      assert test_user.owned_projects.exists?(name: "Demo Project")
      assert User.exists?(email: "free@screenote.app")
    ensure
      subscription&.update_columns(original_subscription_attributes) if original_subscription_attributes
    end

    private

    def claim(
      email: CLAIM_EMAIL,
      password: VALID_PASSWORD,
      password_confirmation: VALID_PASSWORD,
      channel: "web"
    )
      Claim.call(email:, password:, password_confirmation:, channel:)
    end

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

    def saas_deployment
      Screenote::Deployment.new(
        {
          "SCREENOTE_EDITION" => "saas",
          "SCREENOTE_BASE_URL" => "http://screenote.internal"
        },
        production: false
      )
    end

    def with_current_deployment(deployment)
      previous = Screenote::Deployment.current
      Screenote::Deployment.instance_variable_set(:@current, deployment)
      yield
    ensure
      Screenote::Deployment.instance_variable_set(:@current, previous)
    end

    def clean_claim_records
      InstallationAuditEvent.delete_all
      Installation.delete_all
      User.where(email: CLAIM_EMAIL).destroy_all
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
