# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class UserCapabilityTest < ActiveSupport::TestCase
  Deployment = Data.define(:billing?, :saas?, :saas_operator_email)

  test "self-hosted core is unlimited without consulting subscriptions or quota records" do
    deployment = Deployment.new(billing?: false, saas?: false, saas_operator_email: nil)
    user = users(:bob)
    project = projects(:alice_project)
    user.association(:subscription).reset

    queries = capture_queries do
      assert_not user.pro?(deployment: deployment)
      assert user.can_create_project?(deployment: deployment)
      assert user.can_invite_member?(project, deployment: deployment)
    end

    assert_empty queries
  end

  test "SaaS capabilities preserve subscription quotas" do
    deployment = Deployment.new(billing?: true, saas?: true, saas_operator_email: "admin@example.com")
    free_user = users(:bob)
    pro_user = users(:alice)

    assert_not free_user.can_create_project?(deployment: deployment)
    assert pro_user.can_create_project?(deployment: deployment)
    assert pro_user.pro?(deployment: deployment)
  end

  test "the hosted operator identity is edition-bound and is not a generic administrator flag" do
    hosted = Deployment.new(billing?: true, saas?: true, saas_operator_email: "admin@example.com")
    self_hosted = Deployment.new(billing?: false, saas?: false, saas_operator_email: nil)
    user = users(:admin)

    assert user.saas_operator?(deployment: hosted)
    assert_not user.saas_operator?(deployment: self_hosted)
    assert_not user.respond_to?(:admin?)
  end

  private

  def capture_queries
    queries = []
    callback = lambda do |_name, _started, _finished, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      queries << payload.fetch(:sql)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end
end
