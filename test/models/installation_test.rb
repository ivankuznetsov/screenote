# frozen_string_literal: true

require "test_helper"

class InstallationTest < ActiveSupport::TestCase
  setup do
    Installation.delete_all
  end

  test "prepare creates the one unclaimed self hosted installation" do
    deployment = self_hosted_deployment

    installation = Installations::Prepare.call(deployment: deployment)

    assert_equal "screenote", installation.singleton_key
    assert_equal "self_hosted", installation.deployment_mode
    assert_equal "unclaimed", installation.state
    assert_equal "self_hosted_local", installation.storage_service
    assert_equal deployment.storage_namespace_fingerprint, installation.storage_namespace_fingerprint
    assert_nil installation.bootstrap_token_digest
    assert_nil installation.administrator_id
    assert_nil installation.claimed_at
  end

  test "prepare creates SaaS identity without bootstrap state" do
    installation = Installations::Prepare.call(deployment: saas_deployment)

    assert_equal "saas", installation.deployment_mode
    assert_equal "saas", installation.state
    assert_equal "rabata", installation.storage_service
    assert installation.saas?
    assert_not installation.self_hosted?
  end

  test "ownership and storage validation reject every cross-edition state" do
    valid_attributes = {
      singleton_key: Installation::SINGLETON_KEY,
      storage_namespace_fingerprint: "f" * 64
    }

    invalid_installations = [
      Installation.new(valid_attributes.merge(
        deployment_mode: "self_hosted",
        state: "saas",
        storage_service: "self_hosted_local"
      )),
      Installation.new(valid_attributes.merge(
        deployment_mode: "retired",
        state: "claimed",
        storage_service: "retired"
      )),
      Installation.new(valid_attributes.merge(
        deployment_mode: "saas",
        state: "saas",
        storage_service: "self_hosted_local"
      )),
      Installation.new(valid_attributes.merge(
        deployment_mode: "self_hosted",
        state: "unclaimed",
        storage_service: "rabata"
      ))
    ]

    invalid_installations.each do |installation|
      assert_not installation.valid?
      assert installation.errors[:state].any? || installation.errors[:storage_service].any?
    end
  end

  test "restart verifies identity without touching the row" do
    installation = Installations::Prepare.call(deployment: self_hosted_deployment)
    original_updated_at = installation.updated_at

    travel 1.minute do
      restarted = Installations::Prepare.call(deployment: self_hosted_deployment)

      assert_equal installation.id, restarted.id
      assert_equal original_updated_at, restarted.updated_at
    end
  end

  test "claimed installation may restart without bootstrap material" do
    administrator = users(:alice)
    installation = Installations::Prepare.call(deployment: self_hosted_deployment)
    installation.update!(
      state: "claimed",
      administrator: administrator,
      claimed_at: Time.current
    )

    restarted = Installations::Prepare.call(deployment: self_hosted_deployment)

    assert_equal installation.id, restarted.id
    assert_equal "claimed", restarted.state
    assert_equal administrator, restarted.administrator
  end

  test "edition mismatch fails without changing the existing row" do
    installation = Installations::Prepare.call(deployment: saas_deployment)
    attributes = installation.attributes

    error = assert_raises(Installations::Prepare::ConfigurationMismatch) do
      Installations::Prepare.call(deployment: self_hosted_deployment)
    end

    assert_match "deployment mode", error.message
    assert_equal attributes, installation.reload.attributes
  end

  test "storage identity mismatch fails while credential rotation is allowed" do
    original = self_hosted_deployment(
      "SCREENOTE_STORAGE" => "s3",
      "SCREENOTE_S3_ENDPOINT" => "https://objects.example.test",
      "SCREENOTE_S3_REGION" => "local",
      "SCREENOTE_S3_BUCKET" => "screenote",
      "SCREENOTE_S3_PREFIX" => "team-one",
      "SCREENOTE_S3_ACCESS_KEY_ID" => "old-access",
      "SCREENOTE_S3_SECRET_ACCESS_KEY" => "old-secret"
    )
    installation = Installations::Prepare.call(deployment: original)

    rotated = self_hosted_deployment(
      "SCREENOTE_STORAGE" => "s3",
      "SCREENOTE_S3_ENDPOINT" => "https://objects.example.test",
      "SCREENOTE_S3_REGION" => "local",
      "SCREENOTE_S3_BUCKET" => "screenote",
      "SCREENOTE_S3_PREFIX" => "team-one",
      "SCREENOTE_S3_ACCESS_KEY_ID" => "new-access",
      "SCREENOTE_S3_SECRET_ACCESS_KEY" => "new-secret"
    )
    assert_equal installation.id, Installations::Prepare.call(deployment: rotated).id

    changed_namespace = self_hosted_deployment(
      "SCREENOTE_STORAGE" => "s3",
      "SCREENOTE_S3_ENDPOINT" => "https://objects.example.test",
      "SCREENOTE_S3_REGION" => "local",
      "SCREENOTE_S3_BUCKET" => "other-bucket",
      "SCREENOTE_S3_PREFIX" => "team-one",
      "SCREENOTE_S3_ACCESS_KEY_ID" => "new-access",
      "SCREENOTE_S3_SECRET_ACCESS_KEY" => "new-secret"
    )

    error = assert_raises(Installations::Prepare::ConfigurationMismatch) do
      Installations::Prepare.call(deployment: changed_namespace)
    end
    assert_match "storage namespace", error.message
  end

  test "database constraints reject a second singleton and invalid state combinations" do
    installation = Installations::Prepare.call(deployment: saas_deployment)

    assert_raises(ActiveRecord::RecordNotUnique) do
      Installation.transaction(requires_new: true) do
        Installation.insert_all!([ installation.attributes.except("id", "created_at", "updated_at") ])
      end
    end

    assert_raises(ActiveRecord::StatementInvalid) do
      Installation.transaction(requires_new: true) do
        Installation.insert_all!([ {
          singleton_key: "screenote",
          deployment_mode: "self_hosted",
          state: "claimed",
          storage_service: "self_hosted_local",
          storage_namespace_fingerprint: "a" * 64,
          created_at: Time.current,
          updated_at: Time.current
        } ])
      end
    end
  end

  test "database schema keeps only the transition column for predecessor compatibility" do
    assert Installation.column_names.include?("bootstrap_token_digest")
    assert Installation.validators_on(:bootstrap_token_digest).any?
  end

  private

  def self_hosted_deployment(overrides = {})
    Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal",
        "SECRET_KEY_BASE" => "a" * 64
      }.merge(overrides),
      production: true
    )
  end

  def saas_deployment
    Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "saas",
        "SCREENOTE_BASE_URL" => "https://screenote.ai",
        "SECRET_KEY_BASE" => "a" * 64,
        "DATABASE_URL" => "postgres://screenote:secret@db/screenote",
        "CACHE_DATABASE_URL" => "postgres://screenote:secret@db/cache",
        "QUEUE_DATABASE_URL" => "postgres://screenote:secret@db/queue",
        "CABLE_DATABASE_URL" => "postgres://screenote:secret@db/cable",
        "STRIPE_SECRET_KEY" => "stripe-secret",
        "STRIPE_WEBHOOK_SECRET" => "webhook-secret",
        "STRIPE_PRO_PRICE_ID" => "price-pro",
        "RESEND_API_KEY" => "resend-secret",
        "MAILER_FROM" => "noreply@screenote.ai",
        "GOOGLE_CLIENT_ID" => "google-client",
        "GOOGLE_CLIENT_SECRET" => "google-secret",
        "GITHUB_CLIENT_ID" => "github-client",
        "GITHUB_CLIENT_SECRET" => "github-secret",
        "HONEYBADGER_API_KEY" => "honeybadger-secret",
        "HONEYBADGER_JS_API_KEY" => "browser-secret",
        "SCREENOTE_SAAS_OPERATOR_EMAIL" => "operator@screenote.ai",
        "RABATA_ENDPOINT" => "https://s3.us-east-1.rabata.io",
        "RABATA_REGION" => "us-east-1",
        "RABATA_BUCKET" => "screenote",
        "RABATA_ACCESS_KEY_ID" => "access-key",
        "RABATA_SECRET_ACCESS_KEY" => "secret-key"
      },
      production: true
    )
  end
end
