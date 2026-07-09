# frozen_string_literal: true

require "test_helper"

class NotificationMailerPreviewTest < ActionMailer::TestCase
  test "resolution digest single preview renders expected content" do
    email = NotificationMailerPreview.new.resolution_digest_single

    assert_includes email.subject, "[Screenote]"
    assert_includes email.subject, "annotation"
    assert_includes email.body.to_s, "Feedback Resolved"
    assert_includes email.body.to_s, "resolved"
  end

  test "resolution digest multiple preview renders expected content" do
    email = NotificationMailerPreview.new.resolution_digest_multiple

    assert_includes email.subject, "[Screenote]"
    assert_includes email.body.to_s, "Feedback Resolved"
    assert_includes email.body.to_s, "annotation"
  end

  test "resolution digest with reply preview renders reply content" do
    email = NotificationMailerPreview.new.resolution_digest_with_reply

    assert_includes email.subject, "[Screenote]"
    assert_includes email.body.to_s, "Feedback Resolved"
    assert_includes email.body.to_s, "Reply"
  end
end
