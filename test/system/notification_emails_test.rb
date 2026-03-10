# frozen_string_literal: true

require_relative "application_system_test_case"

class NotificationEmailsTest < ApplicationSystemTestCase
  test "resolution digest single preview renders without errors" do
    visit "/rails/mailers/notification_mailer/resolution_digest_single"

    assert_no_selector "header.internal", text: "Error", wait: 5
    assert_selector "body", wait: 10

    within_mailer_preview do |preview|
      assert_content_includes preview, "Feedback Resolved"
      assert_content_includes preview, "annotation"
      assert_content_includes preview, "resolved"
    end
  end

  test "resolution digest multiple preview renders without errors" do
    visit "/rails/mailers/notification_mailer/resolution_digest_multiple"

    assert_no_selector "header.internal", text: "Error", wait: 5
    assert_selector "body", wait: 10

    within_mailer_preview do |preview|
      assert_content_includes preview, "Feedback Resolved"
      assert_content_includes preview, "annotation"
    end
  end

  test "resolution digest with reply preview renders without errors" do
    visit "/rails/mailers/notification_mailer/resolution_digest_with_reply"

    assert_no_selector "header.internal", text: "Error", wait: 5
    assert_selector "body", wait: 10

    within_mailer_preview do |preview|
      assert_content_includes preview, "Feedback Resolved"
      assert_content_includes preview, "Reply"
    end
  end

  test "resolution digest single preview has correct subject" do
    visit "/rails/mailers/notification_mailer/resolution_digest_single"
    assert_selector "body", wait: 10

    assert_selector "dd", text: /\[Screenote\].*annotation.*resolved/, wait: 10
  end

  private

  def within_mailer_preview(&block)
    with_playwright_page do |pw_page|
      iframe = pw_page.frame_locator("iframe")
      yield iframe
    end
  end

  def assert_content_includes(frame_locator, text)
    body = frame_locator.locator("body")
    body.wait_for(state: "visible", timeout: 10_000)
    content = body.text_content
    assert content.include?(text), "Expected email preview to contain '#{text}' but got: #{content.truncate(200)}"
  end
end
