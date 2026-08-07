# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "json"
require "open3"

class U4RoutesTest < ActiveSupport::TestCase
  ROUTE_PROBE = <<~'RUBY'
    routes = Rails.application.routes.routes.map do |route|
      {
        name: route.name&.to_s,
        verb: route.verb,
        path: route.path.spec.to_s,
        controller: route.defaults[:controller],
        action: route.defaults[:action],
        purpose: route.path.requirements[:purpose]&.source
      }
    end
    puts "SCREENOTE_ROUTES=#{JSON.generate(routes)}"
  RUBY

  test "self-hosted mode exposes bootstrap and sends the root to it" do
    routes = routes_for("self_hosted")

    assert_route routes, verb: "GET", path: "/bootstrap(.:format)", controller: "bootstrap", action: "show"
    assert_route routes, verb: "POST", path: "/bootstrap(.:format)", controller: "bootstrap", action: "create"
    assert_route routes, name: "root", verb: "GET", path: "/", controller: "bootstrap", action: "show"
    assert_route routes, name: "new_session", verb: "GET", path: "/session/new(.:format)",
      controller: "sessions", action: "new"
    assert_not routes.any? { |route| route.fetch("name") == "sign_up" }
    assert_not routes.any? { |route| route.fetch("name") == "new_password" }
    assert_route routes, name: "instance_accounts", verb: "GET",
      path: "/instance/accounts(.:format)", controller: "instance/accounts", action: "index"
    assert_route routes, name: "account_recovery", verb: "GET",
      path: "/account-recovery(.:format)", controller: "account_recoveries", action: "show"
    %w[subscription checkout_subscription portal_subscription admin_dashboard].each do |name|
      assert_not routes.any? { |route| route.fetch("name") == name }
    end
    assert_not routes.any? { |route| route.fetch("controller") == "stripe_webhooks" }
    assert_not routes.any? { |route| %w[/terms(.:format) /privacy(.:format)].include?(route.fetch("path")) }
  end

  test "SaaS mode keeps its landing root and does not expose bootstrap" do
    routes = routes_for("saas")

    assert_route routes, name: "root", verb: "GET", path: "/", controller: "static_pages", action: "landing"
    assert_not routes.any? { |route| route.fetch("controller") == "bootstrap" }
    assert_route routes, name: "new_session", verb: "GET", path: "/session/new(.:format)",
      controller: "sessions", action: "new"
    assert_route routes, name: "sign_up", verb: "GET", path: "/sign_up(.:format)",
      controller: "registrations", action: "new"
    assert_route routes, name: "edit_password", verb: "GET", path: "/password-reset(.:format)",
      controller: "passwords", action: "edit"
    assert_route routes, name: "magic_link", verb: "GET", path: "/magic-link(.:format)",
      controller: "magic_links", action: "show"
    assert_route routes, name: "confirmation", verb: "GET", path: "/confirmation(.:format)",
      controller: "confirmations", action: "show"
    assert_not routes.any? { |route| route.fetch("name") == "instance_accounts" }
    assert_route routes, name: "subscription", verb: "GET", path: "/subscription(.:format)",
      controller: "subscriptions", action: "show"
    assert_route routes, name: "checkout_subscription", verb: "POST",
      path: "/subscription/checkout(.:format)", controller: "subscriptions", action: "checkout"
    assert_route routes, name: "portal_subscription", verb: "POST",
      path: "/subscription/portal(.:format)", controller: "subscriptions", action: "portal"
    assert_route routes, verb: "POST", path: "/stripe/webhooks(.:format)",
      controller: "stripe_webhooks", action: "create"
    assert_route routes, name: "admin_dashboard", verb: "GET", path: "/admin/dashboard(.:format)",
      controller: "admin/dashboard", action: "show"
    assert_route routes, verb: "GET", path: "/terms(.:format)", controller: "static_pages", action: "terms"
    assert_route routes, verb: "GET", path: "/privacy(.:format)", controller: "static_pages", action: "privacy"
  end

  test "both modes expose allowlisted authentication exchange and tokenless invitation routes" do
    %w[saas self_hosted].each do |edition|
      routes = routes_for(edition)
      show = assert_route routes,
        name: "authentication_link",
        verb: "GET",
        path: "/authentication-links/:purpose(.:format)",
        controller: "authentication_links",
        action: "show"
      exchange = assert_route routes,
        name: "exchange_authentication_link",
        verb: "POST",
        path: "/authentication-links/:purpose/exchange(.:format)",
        controller: "authentication_links",
        action: "exchange"

      [ show, exchange ].each do |route|
        purpose = Regexp.new("\\A(?:#{route.fetch('purpose')})\\z")
        %w[invitation password_reset magic_link email_confirmation account_recovery].each do |allowed|
          assert_match purpose, allowed
        end
        assert_no_match purpose, "recovery"
      end

      assert_route routes,
        name: "invitation_acceptance",
        verb: "GET",
        path: "/invitation-acceptance(.:format)",
        controller: "invitation_acceptances",
        action: "show"
      assert_route routes,
        verb: "POST",
        path: "/invitation-acceptance(.:format)",
        controller: "invitation_acceptances",
        action: "create"
    end
  end

  test "neither edition exposes legacy raw-token or test-token routes" do
    %w[saas self_hosted].each do |edition|
      routes = routes_for(edition)

      assert_not routes.any? { |route| route.fetch("path").include?("/invitations/:token") }
      assert_not routes.any? { |route| route.fetch("path").include?("/oauth/test_token") }
      assert_not routes.any? { |route| route.fetch("path").include?("/confirmations/:token") }
      assert_not routes.any? { |route| route.fetch("controller").to_s.start_with?("rails_simple_auth/") }
    end
  end

  private

  def routes_for(edition)
    environment = {
      "RAILS_ENV" => "test",
      "SCREENOTE_EDITION" => edition,
      "SCREENOTE_BASE_URL" => "http://screenote.example",
      "PARALLEL_WORKERS" => "1"
    }
    stdout, stderr, status = Open3.capture3(
      environment,
      "bin/rails",
      "runner",
      ROUTE_PROBE,
      chdir: Rails.root.to_s
    )

    assert status.success?, stderr
    payload = stdout.lines.find { |line| line.start_with?("SCREENOTE_ROUTES=") }
    assert payload, "route probe did not emit its payload: #{stdout}"
    JSON.parse(payload.delete_prefix("SCREENOTE_ROUTES="))
  end

  def assert_route(routes, **attributes)
    route = routes.find do |candidate|
      attributes.all? { |key, value| candidate.fetch(key.to_s) == value }
    end

    assert route, -> { "expected route #{attributes.inspect}, got #{routes.inspect}" }
    route
  end
end
