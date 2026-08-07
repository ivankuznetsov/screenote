# frozen_string_literal: true

require "test_helper"

module UserAuthenticationLinks
  class IssueTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    self.use_transactional_tests = false

    Deployment = Data.define(:mail?)

    setup do
      @user = User.create!(
        email: "issue-links-#{SecureRandom.hex(5)}@example.test",
        password: "password123",
        confirmed_at: Time.current
      )
      clear_enqueued_jobs
    end

    teardown do
      AuthenticationToken.where(user_id: @user&.id).delete_all
      @user&.destroy!
      clear_enqueued_jobs
    end

    test "issues one digest-only link and enqueues only integer identifiers" do
      result = Issue.call(
        user: @user,
        purpose: :password_reset,
        deployment: Deployment.new(mail?: true)
      )

      assert_equal :issued, result.status
      assert result.token.outstanding?
      job = enqueued_jobs.last
      assert job
      serialized = job.fetch(:args).inspect
      assert_includes serialized, @user.id.to_s
      assert_includes serialized, result.token.id.to_s
      assert_not_includes serialized, @user.to_global_id.to_s
      assert_not_includes serialized, result.token.token_digest
    end

    test "a replacement supersedes the prior link under the user lock" do
      first = Issue.call(user: @user, purpose: :magic_link, deployment: Deployment.new(mail?: true))
      second = Issue.call(user: @user, purpose: :magic_link, deployment: Deployment.new(mail?: true))

      assert_equal :issued, second.status
      assert first.token.reload.superseded?
      assert_equal first.token.generation + 1, second.token.generation
    end

    test "disabled mail and suspended users issue and enqueue nothing" do
      assert_no_difference [ "AuthenticationToken.count", "enqueued_jobs.size" ] do
        assert_equal :mail_disabled,
          Issue.call(user: @user, purpose: :password_reset, deployment: Deployment.new(mail?: false)).status
      end

      @user.update!(access_status: :suspended)
      assert_no_difference [ "AuthenticationToken.count", "enqueued_jobs.size" ] do
        assert_equal :inactive_user,
          Issue.call(user: @user, purpose: :password_reset, deployment: Deployment.new(mail?: true)).status
      end
    end
  end
end
