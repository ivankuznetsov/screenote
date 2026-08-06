ENV["RAILS_ENV"] ||= "test"

require_relative "support/coverage_boot"

require_relative "../config/environment"
require "rails/test_help"
require_relative "support/device_authorization_test_helper"
require_relative "support/deployment_mode_helper"
require_relative "support/oauth_test_helper"
require_relative "support/principal_action_contract"
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
    include DeviceAuthorizationTestHelper
    include DeploymentModeHelper
    include SnapshotManifestContractHelper
  end
end

require_relative "support/self_hosted_system_installation"

module SignInHelper
  def sign_in(user)
    post session_path, params: { email: user.email, password: "password123" }
  end
end

class ActionDispatch::IntegrationTest
  include SignInHelper
  include OauthTestHelper

  setup do
    @screenote_original_controller_cache_store = ActionController::Base.cache_store
    ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    if defined?(@screenote_original_controller_cache_store)
      ActionController::Base.cache_store = @screenote_original_controller_cache_store
    end
  end
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
