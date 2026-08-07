# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require_relative "../support/instance_administration_test_helper"

class SelfHostedFullFlowTest < ActiveSupport::TestCase
  include InstanceAdministrationTestHelper
  self.use_transactional_tests = false

  setup do
    require_deployment_mode!(:self_hosted)
  end

  teardown do
    Current.reset
    AuthenticationToken.delete_all
    InstallationAuditEvent.delete_all
    Installation.delete_all
  end

  test "active users create multiple projects without billing state" do
    user = users(:free_user)
    principal = AuthenticatedPrincipal.for_user(user)
    subscriptions_before = Subscription.count

    first = Projects::Create.call(
      principal: principal,
      attributes: { name: "Self-hosted core one" }
    )
    second = Projects::Create.call(
      principal: principal,
      attributes: { name: "Self-hosted core two" }
    )

    assert first.persisted?
    assert second.persisted?
    assert first.owner?(user)
    assert second.owner?(user)
    assert_equal subscriptions_before, Subscription.count
    assert_not Screenote::Deployment.current.billing?
  end

  test "project key collaboration remains isolated from every other project" do
    alice_project = projects(:alice_project)
    alice_key = api_keys(:alice_key)
    screenshot = screenshots(:alice_screenshot)
    Current.authenticated_principal = AuthenticatedPrincipal.for_api_key(alice_key)

    created = JSON.parse(CreateAnnotationTool.new.call(
      project_id: alice_project.id,
      screenshot_id: screenshot.id,
      x_percent: 11.0,
      y_percent: 22.0,
      width_percent: 13.0,
      height_percent: 14.0,
      comment: "Self-hosted area contract"
    ))
    annotation_id = created.dig("annotation", "id")
    assert annotation_id

    reply = JSON.parse(AddAnnotationCommentTool.new.call(
      project_id: alice_project.id,
      annotation_id: annotation_id,
      body: "Self-hosted reply contract"
    ))
    assert_equal "Self-hosted reply contract", reply.dig("comment", "body")

    resolved = JSON.parse(ResolveAnnotationTool.new.call(
      project_id: alice_project.id,
      annotation_id: annotation_id
    ))
    assert_equal "resolved", resolved.dig("annotation", "status")

    foreign = JSON.parse(ListAnnotationsTool.new.call(
      project_id: projects(:bob_project).id
    ))
    assert_equal "forbidden", foreign.fetch("error")
  end

  test "suspension invalidates the target and issuer credentials without touching unrelated owners" do
    administrator = users(:admin)
    target = users(:alice)
    target_key = api_keys(:alice_key)
    unrelated_key = api_keys(:bob_key)
    prepare_claimed_installation(administrator: administrator)
    Session.create!(user: target, ip_address: "127.0.0.1", user_agent: "U8")

    assert AuthenticatedPrincipal.for_user(target)
    assert AuthenticatedPrincipal.for_api_key(target_key)
    assert AuthenticatedPrincipal.for_api_key(unrelated_key)

    result = InstanceAccounts::Suspend.call(actor: administrator, target: target)

    assert_equal :suspended, result.status
    assert target.reload.suspended?
    assert target_key.reload.revoked?
    assert_not unrelated_key.reload.revoked?
    assert_not Session.exists?(user_id: target.id)
    assert_nil AuthenticatedPrincipal.for_user(target)
    assert_nil AuthenticatedPrincipal.for_api_key(target_key)
    assert AuthenticatedPrincipal.for_api_key(unrelated_key)
  end

  test "instance administrator receives no implicit project visibility" do
    administrator = users(:admin)
    prepare_claimed_installation(administrator: administrator)

    principal = AuthenticatedPrincipal.for_user(administrator)

    assert_nil principal.resolve_project(projects(:alice_project).id)
    assert_nil principal.resolve_project(projects(:bob_project).id)
    assert_empty administrator.projects
  end
end
