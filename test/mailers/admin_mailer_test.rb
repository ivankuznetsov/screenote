# frozen_string_literal: true

require "test_helper"

class AdminMailerTest < ActionMailer::TestCase
  test "new_pro_subscriber sends email to admin" do
    user = users(:bob)
    email = AdminMailer.new_pro_subscriber(user)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ User::ADMIN_EMAIL ], email.to
    assert_includes email.subject, user.email
    assert_includes email.body.encoded, user.email
    assert_includes email.body.encoded, "Pro"
  end
end
