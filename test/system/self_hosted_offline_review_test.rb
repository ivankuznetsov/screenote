# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/projects_page"
require_relative "pages/pages_page"
require_relative "pages/screenshots_page"
require_relative "pages/annotations_page"
require "ipaddr"

class SelfHostedOfflineReviewTest < ApplicationSystemTestCase
  include Pages::ProjectsPage
  include Pages::PagesPage
  include Pages::ScreenshotsPage
  include Pages::AnnotationsPage

  setup do
    skip "run with SCREENOTE_EDITION=self_hosted" unless Screenote::Deployment.current.self_hosted?

    @external_requests = []
    deny_external_browser_requests
    login_as_test_user
    create_review
  end

  test "provider-free review loads local assets and creates an annotation offline" do
    assert_screenshot_image_loaded
    assert_selector ".a9s-annotationlayer", wait: 15

    with_playwright_page do |browser_page|
      overlay = browser_page.locator(".a9s-annotationlayer").first
      bounds = overlay.bounding_box
      browser_page.mouse.click(
        bounds.fetch("x") + (bounds.fetch("width") * 0.35),
        bounds.fetch("y") + (bounds.fetch("height") * 0.35)
      )
    end

    assert_in_place_annotation_form_visible
    fill_annotation_comment("Offline review works")
    submit_annotation

    assert_annotation_visible("Offline review works")
    assert_empty @external_requests,
      "provider-free review attempted external requests: #{@external_requests.join(', ')}"
  end

  private

  def deny_external_browser_requests
    with_playwright_page do |browser_page|
      browser_page.route("**/*", lambda do |route, request|
        uri = URI.parse(request.url)
        if uri.is_a?(URI::HTTP) && !local_browser_host?(uri.host)
          @external_requests << request.url
          route.abort
        else
          route.continue
        end
      end)
    end
  end

  def local_browser_host?(host)
    host == "localhost" || IPAddr.new(host).loopback?
  rescue IPAddr::InvalidAddressError
    false
  end

  def create_review
    navigate_to_demo_project
    navigate_to_first_page
    click_link "Upload version"
    fill_screenshot_form(title: "Offline review", image_path: TEST_IMAGE_PATH)
    submit_screenshot_form
    assert_on_screenshot_show
  end
end
