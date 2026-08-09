require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative "../lib/screenote/deployment"
require_relative "../lib/screenote/monitoring"
require_relative "../lib/screenote/rate_limit_store"
require_relative "../lib/screenote/trusted_proxy_headers"

Screenote::Deployment.configure!(production: Rails.env.production?)

module ScreenoteTmp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Screenshot bytes are private project data. They are delivered only by
    # MediaController, which rechecks project membership for every request.
    config.active_storage.draw_routes = false

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.x.screenote.deployment = Screenote::Deployment.current
    config.middleware.insert_before 0,
      Screenote::TrustedProxyHeaders,
      trusted_proxies: Screenote::Deployment.current.trusted_proxies,
      forwarded_client_hops: Screenote::Deployment.current.forwarded_client_hops,
      forwarded_proxy_host: Screenote::Deployment.current.forwarded_proxy_host,
      canonical_scheme: Screenote::Deployment.current.protocol
    config.middleware.insert_before 0, Screenote::RateLimitFailureMiddleware

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
