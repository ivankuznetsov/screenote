# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class OfflineAssetsTest < ActionDispatch::IntegrationTest
  ANNOTORIOUS_SHA256 = "4c95eb1ca1f7e4a22cbf4e0372cc39691efd5807a44d3d4623a221257a2d518f"
  EXTERNAL_RUNTIME_ORIGINS = %w[
    cdn.jsdelivr.net
    fonts.googleapis.com
    fonts.gstatic.com
    js.honeybadger.io
  ].freeze

  test "Annotorious is pinned to the reviewed local bundle" do
    importmap = Rails.root.join("config/importmap.rb").read
    bundle = Rails.root.join("vendor/javascript/annotorious.es.js")

    assert_includes importmap, 'pin "@annotorious/annotorious", to: "annotorious.es.js"'
    assert_not_includes importmap, "cdn.jsdelivr.net"
    assert bundle.file?
    assert_equal ANNOTORIOUS_SHA256, Digest::SHA256.file(bundle).hexdigest
  end

  test "provider-free self hosted public and authentication pages request no external runtime assets" do
    with_self_hosted_deployment do
      get root_path
      assert_response :success
      assert_no_external_runtime_origin(response.body)

      get new_session_path
      assert_response :success
      assert_no_external_runtime_origin(response.body)
    end
  end

  private

  def assert_no_external_runtime_origin(document)
    EXTERNAL_RUNTIME_ORIGINS.each do |origin|
      assert_not_includes document, origin
    end
  end

  def with_self_hosted_deployment
    previous = Screenote::Deployment.current
    deployment = Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal",
        "SECRET_KEY_BASE" => "a" * 64
      },
      production: true
    )
    Screenote::Deployment.instance_variable_set(:@current, deployment)
    InstallationAuditEvent.delete_all
    Installation.delete_all
    Installations::Prepare.call(deployment: deployment)
    yield
  ensure
    Screenote::Deployment.instance_variable_set(:@current, previous)
  end
end
