# frozen_string_literal: true

require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "belongs to user" do
    session = sessions(:alice_session)
    assert_equal users(:alice), session.user
  end

  test "active scope returns non-expired sessions" do
    session = sessions(:alice_session)
    assert_includes Session.active, session
  end

  test "expired scope excludes active sessions" do
    session = sessions(:alice_session)
    assert_not_includes Session.expired, session
  end

  test "cleanup_expired deletes old sessions" do
    old_session = users(:alice).sessions.create!(
      ip_address: "127.0.0.1",
      user_agent: "TestAgent",
      created_at: 31.days.ago
    )

    assert_difference "Session.count", -1 do
      Session.cleanup_expired!
    end

    assert_nil Session.find_by(id: old_session.id)
  end
end
