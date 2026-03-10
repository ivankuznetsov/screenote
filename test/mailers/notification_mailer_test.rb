# frozen_string_literal: true

require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  setup do
    @annotation = annotations(:point_annotation)
    @author = @annotation.user # alice
    @resolver = users(:bob)
    @resolution = @annotation.annotation_comments.create!(
      user: @resolver,
      body: "Fixed the button size",
      action: :resolved
    )
  end

  test "resolution_digest is sent to the recipient" do
    email = NotificationMailer.resolution_digest(@author, [ @resolution ])
    assert_emails 1 do
      email.deliver_now
    end
  end

  test "resolution_digest has correct headers" do
    email = NotificationMailer.resolution_digest(@author, [ @resolution ])
    assert_equal [ @author.email ], email.to
    assert_includes email.subject, "[Screenote]"
    assert_includes email.subject, "1 annotation resolved"
  end

  test "subject pluralizes for multiple annotations" do
    region = annotations(:region_annotation)
    resolution2 = region.annotation_comments.create!(
      user: @resolver,
      body: "Fixed the section",
      action: :resolved
    )

    email = NotificationMailer.resolution_digest(@author, [ @resolution, resolution2 ])
    assert_includes email.subject, "2 annotations resolved"
  end

  test "email body contains the original annotation text" do
    email = NotificationMailer.resolution_digest(@author, [ @resolution ])
    assert_includes email.body.to_s, "Button text too small"
  end

  test "email body contains the reply comment when present" do
    @annotation.annotation_comments.create!(
      user: @resolver,
      body: "Increased font size to 16px",
      action: :comment,
      created_at: @resolution.created_at - 1.minute
    )

    email = NotificationMailer.resolution_digest(@author, [ @resolution ])
    assert_includes email.body.to_s, "Increased font size to 16px"
  end

  test "email body contains the resolver info" do
    email = NotificationMailer.resolution_digest(@author, [ @resolution ])
    assert_includes email.body.to_s, @resolver.email
  end

  test "email body contains page and screenshot info" do
    email = NotificationMailer.resolution_digest(@author, [ @resolution ])
    body = email.body.to_s
    assert_includes body, @annotation.screenshot.page.name
    assert_includes body, @annotation.screenshot.title
  end
end
