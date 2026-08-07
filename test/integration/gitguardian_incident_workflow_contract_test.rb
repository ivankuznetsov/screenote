# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"
require "tempfile"
require "yaml"

class GitguardianIncidentWorkflowContractTest < ActiveSupport::TestCase
  WORKFLOW = Rails.root.join(".github/workflows/secrets.yml").freeze
  FIXTURE = Rails.root.join("test/fixtures/releases/gitguardian/multi_page.json").freeze
  BASE_ENV = {
    "EXPECTED_REPOSITORY" => "ivankuznetsov/screenote",
    "GITGUARDIAN_API_KEY" => "fixture-token-never-sent",
    "GITGUARDIAN_SOURCE_ID" => "42",
    "SCREENOTE_GITGUARDIAN_FIXTURE_TEST" => "1"
  }.freeze

  test "metadata gate checks no code out and uses no third party action" do
    workflow = WORKFLOW.read

    assert_includes workflow, "pull_request_target:"
    assert_no_match(/actions\/checkout|^\s*uses:/, workflow)
    assert_not_includes workflow, "continue-on-error: true"
    assert_not_includes workflow, "--exit-zero"
    assert_not_includes workflow, "--ignore-known-secrets"
    assert_not_includes workflow, "--show-secrets"

    script = workflow_script
    pending_index = script.index('state: "pending"')
    source_request_index = script.index("source_uri = URI.join")
    success_index = script.index('state: "success"')
    assert_operator pending_index, :<, source_request_index
    assert_operator source_request_index, :<, success_index
    assert_includes script, 'state: "error"'
    assert_equal 2, script.scan("publish_error_statuses(repository, status_shas, status_token)").length
  end

  test "all pages with only closed incidents pass without exposing incident identifiers" do
    stdout, stderr, status = run_gate

    assert status.success?, stderr
    assert_equal "GitGuardian repository incident gate passed: 2 incident(s), 2 page(s), 0 open\n", stdout
    assert_empty stderr
    assert_not_includes stdout, "11"
    assert_not_includes stdout, "12"
  end

  test "missing credentials fail before any network request" do
    stdout, stderr, status = run_script(env: {}, fixture: nil)

    assert_not status.success?
    assert_empty stdout
    assert_includes stderr, "is not configured"
  end

  test "missing unknown disabled archived and deleted source states fail closed" do
    cases = {
      "missing" => ->(source) { source.delete("monitoring_status") },
      "unknown" => ->(source) { source["monitoring_status"] = "new_provider_state" },
      "disabled" => ->(source) { source["monitoring_status"] = "disabled" },
      "archived" => ->(source) { source["provider_metadata"]["archived"] = true },
      "deleted" => ->(source) { source["deleted"] = true },
      "missing archived" => ->(source) { source["provider_metadata"].delete("archived") },
      "missing deleted" => ->(source) { source.delete("deleted") },
      "null archived" => ->(source) { source["provider_metadata"]["archived"] = nil },
      "string deleted" => ->(source) { source["deleted"] = "false" }
    }

    cases.each do |label, mutation|
      fixture = base_fixture
      source = JSON.parse(fixture.dig("responses", 0, "body"))
      mutation.call(source)
      fixture.dig("responses", 0)["body"] = JSON.generate(source)

      _stdout, stderr, status = run_gate(fixture: fixture)

      assert_not status.success?, "#{label} monitoring state unexpectedly passed"
      assert_match(/monitoring is not active|archived or deleted/, stderr)
    end
  end

  test "source mismatch and malformed provider metadata fail closed" do
    fixtures = []
    mismatch = base_fixture
    rewrite_source(mismatch) { |source| source["full_name"] = "someone/else" }
    fixtures << mismatch
    malformed = base_fixture
    rewrite_source(malformed) { |source| source["provider_metadata"] = [] }
    fixtures << malformed

    fixtures.each do |fixture|
      stdout, stderr, status = run_gate(fixture: fixture)

      assert_not status.success?
      assert_empty stdout
      assert_match(/does not match|metadata is malformed/, stderr)
      assert_not_includes stderr, "someone/else"
    end
  end

  test "malformed JSON unknown statuses duplicate incidents and open incidents fail closed" do
    cases = []
    malformed = base_fixture
    malformed.dig("responses", 1)["body"] = "not-json"
    cases << malformed
    unknown = base_fixture
    unknown.dig("responses", 1)["body"] = '[{"id":11,"status":"FUTURE"}]'
    cases << unknown
    duplicate = base_fixture
    duplicate.dig("responses", 2)["body"] = '[{"id":11,"status":"IGNORED"}]'
    cases << duplicate
    %w[TRIGGERED ASSIGNED].each do |open_status|
      fixture = base_fixture
      fixture.dig("responses", 1)["body"] = JSON.generate([ { "id" => 11, "status" => open_status } ])
      cases << fixture
    end

    cases.each do |fixture|
      stdout, stderr, status = run_gate(fixture: fixture)

      assert_not status.success?
      assert_empty stdout
      assert_includes stderr, "GitGuardian repository incident gate failed"
      assert_no_match(/\bid=(?:11|12)\b|\"id\"/, stderr)
    end
  end

  test "duplicate unsafe repeated and looping pagination links fail closed" do
    next_url = base_fixture.dig("responses", 2, "url")
    fixtures = []

    duplicate = base_fixture
    duplicate.dig("responses", 1, "headers")["link"] = "<#{next_url}>; rel=\"next\", <#{next_url}>; rel=\"next\""
    fixtures << duplicate

    unsafe = base_fixture
    unsafe.dig("responses", 1, "headers")["link"] =
      "<https://attacker.invalid/v1/sources/42/incidents/secrets?per_page=100&cursor=next_AA==>; rel=\"next\""
    fixtures << unsafe

    repeated = base_fixture
    repeated.dig("responses", 1, "headers")["link"] =
      "<#{next_url}&cursor=second>; rel=\"next\""
    fixtures << repeated

    looping = base_fixture
    looping.dig("responses", 2, "headers")["link"] = "<#{next_url}>; rel=\"next\""
    fixtures << looping

    fixtures.each do |fixture|
      stdout, stderr, status = run_gate(fixture: fixture)

      assert_not status.success?
      assert_empty stdout
      assert_match(/pagination|unsafe|duplicate next/, stderr)
    end
  end

  test "API failures fail closed without reflecting response bodies" do
    fixture = base_fixture
    fixture.dig("responses", 1)["status"] = 503
    fixture.dig("responses", 1)["body"] = "private provider detail"

    stdout, stderr, status = run_gate(fixture: fixture)

    assert_not status.success?
    assert_empty stdout
    assert_includes stderr, "HTTP 503"
    assert_not_includes stderr, "private provider detail"
  end

  private

  def base_fixture
    JSON.parse(FIXTURE.read)
  end

  def rewrite_source(fixture)
    source = JSON.parse(fixture.dig("responses", 0, "body"))
    yield source
    fixture.dig("responses", 0)["body"] = JSON.generate(source)
  end

  def run_gate(fixture: base_fixture)
    run_script(env: BASE_ENV, fixture: fixture)
  end

  def run_script(env:, fixture:)
    Tempfile.create([ "screenote-gitguardian-gate", ".rb" ]) do |script|
      script.write(workflow_script)
      script.flush

      if fixture
        Tempfile.create([ "screenote-gitguardian-fixture", ".json" ]) do |file|
          file.write(JSON.generate(fixture))
          file.flush
          return Open3.capture3(env, RbConfig.ruby, script.path, file.path, unsetenv_others: true)
        end
      end

      Open3.capture3(env, RbConfig.ruby, script.path, unsetenv_others: true)
    end
  end

  def workflow_script
    parsed = YAML.safe_load(WORKFLOW.read, permitted_classes: [], aliases: false)
    parsed.fetch("jobs").fetch("repository-incidents").fetch("steps").first.fetch("run")
  end
end
