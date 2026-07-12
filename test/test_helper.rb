ENV["RAILS_ENV"] ||= "test"

if ENV["COVERAGE"] == "true"
  require "simplecov"

  SimpleCov.command_name "rails-test-#{ENV.fetch('TEST_ENV_NUMBER', '0')}"
  SimpleCov.minimum_coverage 100
  SimpleCov.enable_coverage :branch
  SimpleCov.minimum_coverage line: 100, branch: 100
  SimpleCov.start "rails" do
    add_filter "/test/"
    add_filter "/config/"
    add_filter "/db/"
    add_filter "/vendor/"
  end
end

require_relative "../config/environment"
require "rails/test_help"
require_relative "support/oauth_test_helper"
require_relative "support/snapshot_manifest_contract_helper"

module ActiveSupport
  class TestCase
    workers =
      if ENV["COVERAGE"] == "true"
        1
      elsif ENV["PARALLEL_WORKERS"]
        ENV["PARALLEL_WORKERS"].to_i
      else
        :number_of_processors
      end

    parallelize(workers: workers)
    fixtures :all
    include SnapshotManifestContractHelper
  end
end

module SignInHelper
  def sign_in(user)
    post session_path, params: { email: user.email, password: "password123" }
  end
end

class ActionDispatch::IntegrationTest
  include SignInHelper
  include OauthTestHelper
end

class ActiveSupport::TestCase
  include OauthTestHelper

  def require_vips!
    require "vips"
    Vips::Image.black(1, 1)
  rescue LoadError => e
    skip "libvips is required for image-processing tests: #{e.message}"
  rescue StandardError => e
    raise unless defined?(FFI::NotFoundError) && e.is_a?(FFI::NotFoundError)

    skip "libvips is required for image-processing tests: #{e.message}"
  end
end
