# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "rubygems/package"
require "tempfile"
require "tmpdir"
require "yaml"
load Rails.root.join("bin/release-validate").to_s

class ReleaseArtifactContractTest < ActiveSupport::TestCase
  VALIDATOR = Rails.root.join("bin/release-validate").freeze
  EVIDENCE_FIXTURE = Rails.root.join("test/fixtures/releases/valid-redacted-evidence.json").freeze
  SOURCE_SHA = ("1" * 40).freeze
  RELEASE_TAG = "v1.0.0"
  VALIDATION_TIME = "2026-08-06T01:00:00Z"
  BASE_IMAGE = "docker.io/library/ruby:3.4.10-alpine3.24@sha256:c5a5064d190055633011c03aa800170cc36945ff3afb5f6c915329f92d6f1e00"
  ACTION_REFERENCE = /^\s*uses:\s*([^\s#]+)/

  test "static source release preparation is complete and fail closed" do
    stdout, stderr, status = run_validator("--mode", "prepare")

    assert status.success?, stderr
    assert_equal "release validation passed (prepare)\n", stdout
    assert_empty stderr
  end

  test "GitGuardian configuration fixtures cannot redirect or extend secret scanning" do
    cases = {
      "malicious-instance.json" => ".gitguardian.yaml.instance must equal",
      "unknown-key.json" => ".gitguardian.yaml has unknown keys: proxy"
    }

    cases.each do |fixture_name, expected_error|
      Dir.mktmpdir("screenote-gitguardian-config") do |root|
        fixture = Rails.root.join("test/fixtures/releases/gitguardian", fixture_name)
        FileUtils.cp(fixture, File.join(root, ".gitguardian.yaml"))
        validator = ReleaseValidation.new(root: root)

        validator.send(:gitguardian_configuration)

        assert validator.errors.any? { |error| error.include?(expected_error) }, validator.errors.join("\n")
      end
    end
  end

  test "exact adapted license and source available policies are present" do
    assert_equal "270fc922f0483dc3cc6757c18e2e2c83093b5eeaf1adcf6bd5ff70df3e8790dc",
      Digest::SHA256.file(Rails.root.join("LICENSE")).hexdigest
    assert_includes Rails.root.join("LICENSE").read, "Copyright © 2026, Future Spin Ltd."

    [ "README.md", *ReleaseValidation::SOURCE_BOUNDARY_FILES ].each do |path|
      contents = Rails.root.join(path).read
      assert_match(/source-available|O'Saasy|security|as-is/i, contents, path)
    end

    notices = Rails.root.join("THIRD_PARTY_NOTICES.md").read
    assert_includes notices, "`thruster` 0.1.23"
    assert_not_includes notices, "`thruster` 0.1.18"
    assert_includes notices, "Alpine packages installed by `Dockerfile` with `apk`"
    assert_not_includes notices, "Debian packages installed by `Dockerfile`"

    public_installation_docs = ReleaseValidation::PUBLIC_INSTALLATION_DOCS.sum("") do |path|
      Rails.root.join(path).read
    end
    assert_no_match(/(?:export\s+|environment:.*|[- ]+)RAILS_MASTER_KEY\s*[:=]/i, public_installation_docs)
    assert_no_match(/docker\s+compose|compose\.ya?ml/i, public_installation_docs)
    assert_no_match(/\bmcp\b/i, public_installation_docs)
    assert_not_includes public_installation_docs, "SCREENOTE_BOOTSTRAP_TOKEN"
    assert_not_includes public_installation_docs, "compose.bootstrap.yaml"
    assert_not Rails.root.join("config/credentials.yml.enc").exist?
    gitignore = Rails.root.join(".gitignore").read.lines.map(&:strip)
    assert_includes gitignore, "/config/credentials*.yml.enc"
    assert_includes gitignore, "/config/credentials/**/*.yml.enc"
  end

  test "release validator rejects MCP wording regardless of case" do
    %w[mcp McP].each do |wording|
      with_public_positioning_copy do |root|
        File.open(File.join(root, "README.md"), "a") do |readme|
          readme.puts("Use the #{wording} integration.")
        end

        validator = validate_public_positioning(root)

        assert_includes validator.errors,
          "public product docs must use the CLI and agent skill rather than MCP",
          wording
      end
    end
  end

  test "release validator rejects retired bootstrap installation guidance" do
    {
      "bootstrap token" => "SCREENOTE_BOOTSTRAP_TOKEN",
      "bootstrap overlay" => "compose.bootstrap.yaml"
    }.each do |label, retired_reference|
      with_public_positioning_copy do |root|
        File.open(File.join(root, "README.md"), "a") do |readme|
          readme.puts(retired_reference)
        end

        validator = validate_public_positioning(root)

        assert_includes validator.errors,
          "public installation docs must not mention retired #{retired_reference}",
          label
      end
    end
  end

  test "public self hosted deployment uses the native ONCE installer and normal updates" do
    documents = ReleaseValidation::PUBLIC_INSTALLATION_DOCS.sum("") do |path|
      Rails.root.join(path).read
    end

    assert_includes documents, "curl https://get.once.com/screenote | sh"
    assert_includes documents, "ghcr.io/ivankuznetsov/screenote:latest"
    ReleaseValidation::PUBLIC_ONCE_COMMAND_DOCS.each do |path|
      document = Rails.root.join(path).read
      assert_includes document, "curl https://get.once.com/screenote | sh", path
      commands = ReleaseValidation.new(root: Rails.root).send(:public_shell_commands, document)
      assert commands.any? { |tokens| tokens.first(2) == %w[once update] && tokens.length == 3 }, path
    end

    assert_not Rails.root.join("config/deploy.yml").exist?
    assert_not Rails.root.join(".kamal/secrets.example").exist?
    assert_not Rails.root.join("lib/screenote/kamal_release_deployer.rb").exist?
    assert_includes Rails.root.join("bin/kamal").read, 'load Gem.bin_path("kamal", "kamal")'
  end

  test "release validator rejects unsupported Screenote image identities" do
    cases = {
      "release placeholder" =>
        "ghcr.io/ivankuznetsov/screenote:vX.Y.Z@sha256:REPLACE_WITH_RELEASE_DIGEST",
      "next placeholder" =>
        "ghcr.io/ivankuznetsov/screenote:vNEXT@sha256:REPLACE_WITH_RELEASE_DIGEST",
      "tag without digest" =>
        "ghcr.io/ivankuznetsov/screenote:v1.2.3",
      "malformed release tag" =>
        "ghcr.io/ivankuznetsov/screenote:v1.bad.0@sha256:#{'a' * 64}",
      "malformed manifest digest" =>
        "ghcr.io/ivankuznetsov/screenote:v1.2.3@sha256:not-a-digest"
    }

    cases.each do |label, malformed_reference|
      with_public_positioning_copy do |root|
        readme = File.join(root, "README.md")
        original = File.read(readme)
        mutated = original.sub(
          "ghcr.io/ivankuznetsov/screenote:latest",
          malformed_reference
        )
        assert_not_equal original, mutated, label
        File.write(readme, mutated)

        validator = validate_public_positioning(root)

        assert_includes validator.errors,
          "public installation docs contain an unsupported Screenote image reference",
          label
      end
    end
  end

  test "release validator accepts latest and immutable semantic image references" do
    reference = "ghcr.io/ivankuznetsov/screenote:v1.2.3@sha256:#{'a' * 64}"
    validator = ReleaseValidation.new(root: Rails.root)

    assert validator.send(:valid_public_image_reference?, ReleaseValidation::PUBLIC_RELEASE_IMAGE)
    assert validator.send(:valid_public_image_reference?, reference)
  end

  test "release validator rejects incomplete ONCE installation guidance" do
    cases = {
      "missing native installer" => [
        ->(contents) { contents.gsub("https://get.once.com/screenote", "https://get.once.com/custom") },
        "public installation docs must use Screenote's native ONCE installer"
      ],
      "missing canonical image" => [
        ->(contents) { contents.gsub("ghcr.io/ivankuznetsov/screenote:", "registry.invalid/screenote:") },
        "public installation docs must name the Screenote release image"
      ]
    }

    cases.each do |label, (mutation, expected_error)|
      with_public_positioning_copy do |root|
        ReleaseValidation::PUBLIC_INSTALLATION_DOCS.each do |relative|
          document = File.join(root, relative)
          File.write(document, mutation.call(File.read(document)))
        end

        validator = validate_public_positioning(root)
        assert_includes validator.errors, expected_error, label
      end
    end
  end

  test "release validator checks each copyable ONCE command independently" do
    immutable_release = "ghcr.io/ivankuznetsov/screenote:v1.2.3@sha256:#{'a' * 64}"
    cases = {
      "wrong README installer route" => [
        ->(contents) { contents.sub("curl https://get.once.com/screenote | sh", "curl https://get.once.com/custom | sh") },
        "README.md must include the exact native Screenote ONCE installer command"
      ],
      "image-pinned README update without normal update" => [
        ->(contents) { contents.sub("once update screenote.example.com", "once update screenote.example.com --image #{immutable_release}") },
        "README.md must include a normal bare ONCE update command"
      ]
    }

    cases.each do |label, (mutation, expected_error)|
      with_public_positioning_copy do |root|
        readme = File.join(root, "README.md")
        original = File.read(readme)
        mutated = mutation.call(original)
        assert_not_equal original, mutated, label
        File.write(readme, mutated)

        validator = validate_public_positioning(root)
        assert_includes validator.errors, expected_error, label
      end
    end
  end

  test "complete redacted fixture passes the evidence schema" do
    stdout, stderr, status = run_evidence(EVIDENCE_FIXTURE)

    assert status.success?, stderr
    assert_equal "release validation passed (evidence)\n", stdout
    assert_empty stderr
  end

  test "public evidence separates PR contracts from exact release qualification" do
    fixture = evidence

    assert_equal "pr_contract_only", fixture.dig("source_contracts", "scope")
    assert_not fixture.fetch("source_contracts").key?("status")
    fixture.dig("source_contracts", "required_checks").each do |check|
      assert_equal "success", check.fetch("conclusion")
      assert_not check.key?("status")
    end

    qualification = fixture.fetch("qualification")
    assert_equal "passed", qualification.fetch("status")
    assert_equal ".github/workflows/release-qualification.yml", qualification.fetch("workflow_path")
    assert_equal [
      [ "self-hosted-boot", "linux-amd64" ],
      [ "self-hosted-boot", "linux-arm64" ],
      [ "saas-boot", "linux-amd64" ],
      [ "saas-boot", "linux-arm64" ],
      [ "backup-restore", "minimum-host" ],
      [ "sqlite-load", "minimum-host" ],
      [ "public-cli", "http" ],
      [ "public-cli", "https" ]
    ].sort, qualification.fetch("checks").map { |check| [ check.fetch("name"), check.fetch("target") ] }.sort
  end

  test "qualification evidence fails closed on missing checks and mismatched exact bindings" do
    cases = {
      "missing exact check" => [ ->(document) { document.dig("qualification", "checks").pop }, "qualification.checks is missing" ],
      "candidate bundle" => [ ->(document) { document.dig("qualification")["candidate_sha256"] = "0" * 64 }, "qualification.candidate_sha256" ],
      "manifest" => [ ->(document) { document.dig("qualification")["manifest_digest"] = "sha256:#{'0' * 64}" }, "qualification.manifest_digest" ],
      "platform" => [ ->(document) { document.dig("qualification", "platforms", 0)["digest"] = "sha256:#{'0' * 64}" }, "qualification platform digests" ],
      "CLI" => [ ->(document) { document.dig("qualification")["cli_tag"] = "v2.0.0" }, "qualification.cli_tag" ],
      "run" => [ ->(document) { document.dig("qualification")["workflow_run_id"] = "0" }, "positive-integer string" ]
    }

    cases.each do |label, (mutation, expected_error)|
      assert_rejected(label, expected_error, &mutation)
    end
  end

  test "downloaded qualification record must match exact public evidence bytes" do
    document = evidence
    report = document.fetch("qualification").except("artifact_sha256", "record_sha256")

    Tempfile.create([ "screenote-qualification-record", ".json" ]) do |record_file|
      record_file.write(JSON.pretty_generate(report) << "\n")
      record_file.flush
      document.fetch("qualification")["record_sha256"] = Digest::SHA256.file(record_file.path).hexdigest

      Tempfile.create([ "screenote-evidence-with-qualification", ".json" ]) do |evidence_file|
        evidence_file.write(JSON.generate(document))
        evidence_file.flush
        validator = ReleaseValidation.new(root: Rails.root)
        validator.validate_qualification_record(path: record_file.path, evidence_path: evidence_file.path)
        assert_predicate validator, :success?, validator.errors.join("\n")

        record_file.rewind
        changed = JSON.parse(record_file.read)
        changed["cli_sha"] = "9" * 40
        record_file.rewind
        record_file.truncate(0)
        record_file.write(JSON.generate(changed))
        record_file.flush
        validator = ReleaseValidation.new(root: Rails.root)
        validator.validate_qualification_record(path: record_file.path, evidence_path: evidence_file.path)
        assert_includes validator.errors, "qualification record bytes do not match public evidence"
      end
    end
  end

  test "public evidence contains only technical release gates" do
    example = JSON.parse(Rails.root.join("docs/releases/evidence/public-evidence.example.json").read)
    fixture = evidence
    expected_keys = %w[
      artifacts fixture gitguardian public_artifacts qualification release repository rulesets schema source_contracts
      source_sha vulnerability
    ]

    [ example, fixture ].each do |document|
      assert_equal "screenote-release-evidence/v2", document.fetch("schema")
      assert_equal expected_keys.sort, document.keys.sort
    end

    assert_rejected("obsolete governance field", "unknown keys: preauthorization") do |document|
      document["preauthorization"] = { "status" => "approved" }
    end
  end

  test "missing or mismatched release identity and artifacts fail closed" do
    cases = {
      "source SHA" => [ ->(evidence) { evidence["source_sha"] = "2" * 40 }, "requested source SHA" ],
      "release tag" => [ ->(evidence) { evidence.dig("release")["tag"] = "latest" }, "immutable vMAJOR.MINOR.PATCH" ],
      "predecessor" => [ ->(evidence) { evidence.dig("release").delete("predecessor_tag") }, "missing keys: predecessor_tag" ],
      "CLI tag" => [ ->(evidence) { evidence.dig("release")["cli_tag"] = "main" }, "immutable vMAJOR.MINOR.PATCH" ],
      "SBOM" => [ ->(evidence) { evidence.dig("artifacts")["sbom_sha256"] = nil }, "sbom_sha256 must be" ],
      "provenance" => [ ->(evidence) { evidence.dig("artifacts").delete("provenance_sha256") }, "missing keys: provenance_sha256" ],
      "platform digest" => [ ->(evidence) { evidence.dig("gitguardian", "image_scan", "platforms", 0)["digest"] = "sha256:#{'9' * 64}" }, "must equal" ]
    }

    cases.each do |label, (mutation, expected_error)|
      assert_rejected(label, expected_error, &mutation)
    end
  end

  test "failed technical release gates fail closed" do
    cases = {
      "open incident" => [ ->(evidence) { evidence.dig("gitguardian", "incidents")["open"] = 1 }, "gitguardian.incidents.open" ],
      "unfinished history" => [ ->(evidence) { evidence.dig("gitguardian", "app_check")["history_scan"] = "running" }, "history_scan" ],
      "failed source contract" => [ ->(evidence) { evidence.dig("source_contracts", "required_checks", 0)["conclusion"] = "failure" }, "must equal \"success\"" ],
      "vulnerability" => [ ->(evidence) { evidence.dig("vulnerability")["critical"] = 1 }, "vulnerability.critical" ],
      "ruleset bypass" => [ ->(evidence) { evidence.dig("rulesets")["no_broad_bypass"] = false }, "no_broad_bypass" ],
      "stale incident check" => [ ->(evidence) { evidence.dig("gitguardian", "incidents")["checked_at"] = "2026-08-01T00:00:00Z" }, "older than" ]
    }

    cases.each do |label, (mutation, expected_error)|
      assert_rejected(label, expected_error, &mutation)
    end
  end

  test "expired anonymous broad or unmatched vulnerability waivers fail closed" do
    waiver = {
      "id_sha256" => "5" * 64,
      "severity" => "critical",
      "architecture" => "amd64",
      "image_digest" => "sha256:#{'a' * 64}",
      "finding_id_sha256" => "6" * 64,
      "approver_role" => "security_approver",
      "approved_at" => "2026-07-01T00:00:00Z",
      "expires_at" => "2026-08-01T00:00:00Z",
      "evidence_sha256" => "7" * 64
    }

    assert_rejected("expired waiver", "expires_at must be in the future") do |evidence|
      evidence.dig("vulnerability", "waivers") << waiver
    end
    assert_rejected("anonymous waiver", "approver_role") do |evidence|
      evidence.dig("vulnerability", "waivers") << waiver.merge(
        "approved_at" => "2026-08-05T00:00:00Z",
        "expires_at" => "2026-08-10T00:00:00Z",
        "approver_role" => "anonymous"
      )
    end
    assert_rejected("broad waiver", "lasts longer than 30 days") do |evidence|
      evidence.dig("vulnerability", "waivers") << waiver.merge(
        "approved_at" => "2026-08-05T00:00:00Z",
        "expires_at" => "2026-09-20T00:00:00Z"
      )
    end
    assert_rejected("unmatched waiver", "must equal") do |evidence|
      evidence.dig("vulnerability", "waivers") << waiver.merge(
        "approved_at" => "2026-08-05T00:00:00Z",
        "expires_at" => "2026-08-10T00:00:00Z",
        "image_digest" => "sha256:#{'8' * 64}"
      )
    end
  end

  test "unknown placeholder and sensitive public evidence fields fail closed" do
    assert_rejected("unknown field", "unknown keys: internal") { |evidence| evidence["internal"] = "opaque-record-1" }
    assert_rejected("placeholder", "contains a placeholder") { |evidence| evidence.dig("release")["cli_tag"] = "PENDING" }
    assert_rejected("private path", "prohibited public security detail") do |evidence|
      evidence["internal"] = "/tmp/private-scan-result"
    end
  end

  test "publication sentinel blocks regular files and dangling symlinks in isolated trees" do
    Dir.mktmpdir("screenote-publication-sentinel") do |root|
      blocker = File.join(root, "docs/releases/PUBLICATION_BLOCKED.md")
      FileUtils.mkdir_p(File.dirname(blocker))
      File.write(blocker, "blocked\n")

      validator = ReleaseValidation.new(root: root)
      validator.validate_publication_blocker
      assert_includes validator.errors, "publication sentinel still exists: docs/releases/PUBLICATION_BLOCKED.md"

      FileUtils.rm(blocker)
      File.symlink("missing-target", blocker)
      assert_not File.exist?(blocker)
      assert File.symlink?(blocker)

      validator = ReleaseValidation.new(root: root)
      validator.validate_publication_blocker
      assert_includes validator.errors, "publication sentinel still exists: docs/releases/PUBLICATION_BLOCKED.md"
    end
  end

  test "publication sentinel requires the supported ONCE runtime and recovery drills" do
    sentinel = Rails.root.join("docs/releases/PUBLICATION_BLOCKED.md").read
    checklist = Rails.root.join("docs/releases/publication-checklist.md").read

    [ sentinel, checklist ].each do |document|
      assert_includes document, "ONCE"
      assert_includes document, "ONCE backup"
      assert_includes document, "restart"
      assert_includes document, "persistence"
    end
  end

  test "fixture evidence independently prevents publication" do
    _stdout, stderr, status = run_validator(
      "--mode", "publish",
      "--evidence", EVIDENCE_FIXTURE.to_s,
      "--source-sha", SOURCE_SHA,
      "--tag", RELEASE_TAG,
      "--now", VALIDATION_TIME
    )

    assert_not status.success?
    assert_includes stderr, "fixture evidence cannot authorize publication"
  end

  test "all Actions are immutable and release promotion never checks out source" do
    workflows = Rails.root.glob(".github/workflows/*.{yml,yaml}")
    references = workflows.flat_map do |workflow|
      workflow.readlines.filter_map { |line| line[ACTION_REFERENCE, 1] }
    end

    assert_predicate references, :any?
    references.each do |reference|
      if reference.start_with?("./.github/workflows/")
        assert_equal "./.github/workflows/secrets.yml", reference
      else
        assert_match(/@[0-9a-f]{40}\z/, reference, reference)
      end
    end

    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    promotion = release.fetch("jobs").fetch("promotion")
    assert_equal "authorize", promotion.fetch("needs")
    assert_equal "source-release", promotion.fetch("environment")
    promotion_uses = promotion.fetch("steps").filter_map { |step| step["uses"] }
    assert_no_match(/actions\/checkout/, promotion_uses.join("\n"))
    assert_equal(
      { "actions" => "read", "attestations" => "write", "contents" => "read", "id-token" => "write" },
      promotion.fetch("permissions")
    )
    approval_step = promotion.fetch("steps").first
    assert_equal "current-run-approval", approval_step.fetch("id")
    assert_equal "${{ github.token }}", approval_step.dig("env", "GH_TOKEN")
    assert_nil approval_step.dig("env", "WORKFLOW_RUN_ID")
    assert_includes approval_step.fetch("run"),
      '"/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/approvals"'
    assert_not_includes release.to_yaml, "environment-approval.json"
    assert_not_includes release.to_yaml, "historical-environment-approval"

    secrets = YAML.safe_load(Rails.root.join(".github/workflows/secrets.yml").read, permitted_classes: [], aliases: false)
    incident_job = secrets.fetch("jobs").fetch("repository-incidents")
    assert_equal({ "contents" => "read", "statuses" => "write" }, incident_job.fetch("permissions"))
    incident_source = incident_job.fetch("steps").fetch(0).fetch("run")
    assert_includes incident_source, "PR_HEAD_SHA"
    assert_includes incident_source, "PR_MERGE_SHA"
    assert_includes incident_source, 'URI("https://api.github.com/repos/#{repository}/statuses/#{sha}")'
    assert_no_match(/actions\/checkout|git\s+(?:checkout|show|archive)/, incident_source)

    authorization_source = release.fetch("jobs").fetch("authorize").fetch("steps").find do |step|
      step["id"] == "authorization-source"
    end.fetch("run")
    assert_includes authorization_source, 'git rev-list --reverse "$SOURCE_SHA..$GITHUB_SHA"'
    assert_includes authorization_source, 'test "${#authorization_commits[@]}" -eq 1'
    assert_includes authorization_source, 'test "${authorization_parents[0]}" = "$SOURCE_SHA"'
    assert_includes authorization_source,
      'git diff-tree --no-commit-id --name-status --no-renames -r -z "$SOURCE_SHA" "$GITHUB_SHA"'
    assert_not_includes authorization_source, 'git diff --name-only -z "$SOURCE_SHA" "$GITHUB_SHA"'
    assert_includes authorization_source, "docs/releases/PUBLICATION_BLOCKED.md\" => \"D"
    assert_includes authorization_source, "docs/releases/evidence/public-evidence.json\" => \"A"
    assert_includes authorization_source, "docs/releases/initial-release.md\" => \"M"
    assert_includes authorization_source, "test ! -L docs/releases/PUBLICATION_BLOCKED.md"
  end

  test "candidate and authorization heads use exact step-scoped GitHub API resolution" do
    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    cases = {
      "candidate-source" => [ "Resolve the exact candidate default-branch head", "${{ inputs.source_sha }}" ],
      "authorize" => [ "Resolve the exact authorizing default-branch head", "${{ github.sha }}" ]
    }
    validators = []

    cases.each do |job_name, (step_name, expected_sha)|
      job = release.fetch("jobs").fetch(job_name)
      steps = job.fetch("steps")
      resolution_index = steps.index { |step| step["name"] == step_name }
      checkout_index = steps.index { |step| step.fetch("uses", "").start_with?("actions/checkout@") }
      assert_not_nil resolution_index
      assert_not_nil checkout_index
      assert_operator resolution_index, :<, checkout_index

      resolution = steps.fetch(resolution_index)
      assert_equal "${{ github.event.repository.default_branch }}", resolution.dig("env", "DEFAULT_BRANCH")
      assert_equal expected_sha, resolution.dig("env", "EXPECTED_SHA")
      assert_equal "${{ github.token }}", resolution.dig("env", "GH_TOKEN")
      assert_nil job.dig("env", "GH_TOKEN")
      pre_checkout_token_steps = steps.take(checkout_index).filter_map do |step|
        step["name"] if step.dig("env", "GH_TOKEN") == "${{ github.token }}"
      end
      assert_equal [ step_name ], pre_checkout_token_steps

      checkout = steps.fetch(checkout_index)
      assert_equal false, checkout.dig("with", "persist-credentials")
      source = resolution.fetch("run")
      assert_includes source, '"/repos/$GITHUB_REPOSITORY/git/ref/heads/$DEFAULT_BRANCH"'
      assert_includes source, '"/repos/$GITHUB_REPOSITORY/git/commits/$EXPECTED_SHA"'
      assert_includes source, 'ref["ref"] == expected_ref'
      assert_includes source, 'object["type"] == "commit"'
      assert_includes source, 'object["sha"] == expected_sha'
      assert_includes source, 'commit["sha"] == expected_sha'
      assert_not_includes source, "git fetch"

      validator = source.match(
        /DEFAULT_REF_JSON="\$ref_json" DEFAULT_COMMIT_JSON="\$commit_json" ruby -rjson <<'RUBY'\n(?<ruby>.*?)^RUBY$/m
      )&.named_captures&.fetch("ruby")
      assert_not_nil validator
      validators << validator
    end

    assert_equal 1, validators.uniq.length
    valid_ref = {
      "ref" => "refs/heads/main",
      "object" => { "type" => "commit", "sha" => SOURCE_SHA }
    }
    valid_commit = { "sha" => SOURCE_SHA }
    _stdout, stderr, status = run_head_resolution_validator(validators.first, valid_ref, valid_commit)
    assert status.success?, stderr

    rejected = {
      "different branch" => [ valid_ref.merge("ref" => "refs/heads/release"), valid_commit ],
      "non-commit ref" => [ valid_ref.merge("object" => { "type" => "tag", "sha" => SOURCE_SHA }), valid_commit ],
      "different ref SHA" => [ valid_ref.merge("object" => { "type" => "commit", "sha" => "2" * 40 }), valid_commit ],
      "different commit SHA" => [ valid_ref, { "sha" => "2" * 40 } ]
    }
    rejected.each do |label, (ref, commit)|
      _stdout, _stderr, status = run_head_resolution_validator(validators.first, ref, commit)
      assert_not status.success?, "#{label} unexpectedly passed"
    end

    workflow = Rails.root.join(".github/workflows/release.yml").read
    assert_not_includes workflow, "git fetch --no-tags origin"
  end

  test "candidate workflow identity requires the documented ref-qualified default-branch path" do
    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    step = release.fetch("jobs").fetch("authorize").fetch("steps").find do |candidate_step|
      candidate_step["name"] == "Verify candidate workflow identity"
    end
    assert_equal "${{ github.event.repository.default_branch }}", step.dig("env", "DEFAULT_BRANCH")
    assert_equal "${{ github.repository }}", step.dig("env", "EXPECTED_REPOSITORY")

    validator = step.fetch("run").match(
      /RUN_JSON="\$run" ruby -rjson -e '\n(?<ruby>.*?)^'$/m
    )&.named_captures&.fetch("ruby")
    assert_not_nil validator

    valid_run = {
      "event" => "workflow_dispatch",
      "head_branch" => "main",
      "head_sha" => SOURCE_SHA,
      "conclusion" => "success",
      "path" => ".github/workflows/release.yml@main",
      "repository" => { "full_name" => "ivankuznetsov/screenote" }
    }
    environment = {
      "DEFAULT_BRANCH" => "main",
      "EXPECTED_REPOSITORY" => "ivankuznetsov/screenote",
      "SOURCE_SHA" => SOURCE_SHA
    }
    _stdout, stderr, status = run_candidate_workflow_identity_validator(validator, valid_run, environment)
    assert status.success?, stderr

    rejected = {
      "bare workflow path" => valid_run.merge("path" => ".github/workflows/release.yml"),
      "wrong workflow ref" => valid_run.merge("path" => ".github/workflows/release.yml@release"),
      "wrong head branch" => valid_run.merge("head_branch" => "release"),
      "wrong repository" => valid_run.merge("repository" => { "full_name" => "attacker/screenote" })
    }
    rejected.each do |label, run|
      _stdout, _stderr, status = run_candidate_workflow_identity_validator(validator, run, environment)
      assert_not status.success?, "#{label} unexpectedly passed"
    end
  end

  test "publication live-verifies one exact qualification run artifact and CLI tag" do
    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    authorize_steps = release.fetch("jobs").fetch("authorize").fetch("steps")
    identity = authorize_steps.find { |step| step["id"] == "qualification" }
    download = authorize_steps.find do |step|
      step.fetch("uses", "").start_with?("actions/download-artifact@") && step.dig("with", "artifact-ids")
    end
    bytes = authorize_steps.find { |step| step["name"] == "Verify exact qualification bytes and live CLI tag" }

    assert_not_nil identity
    assert_not_nil download
    assert_not_nil bytes
    source = identity.fetch("run")
    assert_includes source, "/actions/runs/$QUALIFICATION_RUN_ID/attempts/$qualification_attempt"
    assert_includes source, "/actions/runs/$QUALIFICATION_RUN_ID/attempts/$qualification_attempt/jobs?per_page=100"
    assert_includes source, "/actions/runs/$QUALIFICATION_RUN_ID/artifacts?per_page=100"
    assert_includes source, '"path" => ".github/workflows/release-qualification.yml@#{ENV.fetch(\'DEFAULT_BRANCH\')}"'
    assert_includes source, 'artifact["digest"] == "sha256:#{ENV.fetch(\'QUALIFICATION_ARTIFACT_SHA256\')}"'
    assert_includes source, "qualification jobs are missing duplicated or unexpected"
    assert_equal "${{ steps.qualification.outputs.artifact_id }}", download.dig("with", "artifact-ids")
    assert_equal "${{ inputs.qualification_run_id }}", download.dig("with", "run-id")
    assert_includes bytes.fetch("run"), "--mode qualification"
    assert_includes bytes.fetch("run"), "qualification artifact file set does not match"
    assert_includes bytes.fetch("run"), "/repos/ivankuznetsov/screenote-cli/git/ref/tags/$cli_tag"
    assert_includes bytes.fetch("run"), "live CLI tag no longer matches qualification"
  end

  test "release qualification is distinct fail-closed runtime evidence" do
    path = Rails.root.join(".github/workflows/release-qualification.yml")
    qualification = YAML.safe_load(path.read, permitted_classes: [], aliases: false)
    assert_equal [ "workflow_dispatch" ], qualification.fetch(true).keys
    jobs = qualification.fetch("jobs")
    assert_equal %w[configure minimum-host platform record], jobs.keys.sort
    assert_equal [ "self-hosted", "${{ matrix.runner_label }}" ], jobs.dig("platform", "runs-on")
    assert_equal [ "self-hosted", "${{ vars.SCREENOTE_RELEASE_MINIMUM_HOST_RUNNER_LABEL }}" ],
      jobs.dig("minimum-host", "runs-on")

    configure_steps = jobs.fetch("configure").fetch("steps")
    checkout = configure_steps.find { |step| step["name"] == "Checkout exact qualification source" }
    bind = configure_steps.find { |step| step["id"] == "bind" }
    assert_not_nil checkout
    assert_not_nil bind
    assert_equal "${{ inputs.source_sha }}", checkout.dig("with", "ref")
    assert_equal false, checkout.dig("with", "persist-credentials")
    assert_equal "config/release/minimum-host-v1.json", checkout.dig("with", "sparse-checkout")
    assert_equal false, checkout.dig("with", "sparse-checkout-cone-mode")
    assert_includes bind.fetch("run"), 'minimum_host_profile_path="config/release/minimum-host-v1.json"'
    assert_includes bind.fetch("run"), 'test "$(git -C "$GITHUB_WORKSPACE" rev-parse HEAD)" = "$SOURCE_SHA"'
    assert_includes bind.fetch("run"), 'test ! -L "$GITHUB_WORKSPACE/$minimum_host_profile_path"'
    assert_includes bind.fetch("run"), 'sha256sum "$GITHUB_WORKSPACE/$minimum_host_profile_path"'

    workflow = path.read
    assert_not_includes workflow, "pull_request:"
    assert_not_includes workflow, "workflow_run:"
    assert_includes workflow, "candidate_artifact_id"
    assert_includes workflow, "artifact-ids:"
    assert_not_includes workflow, "SCREENOTE_RELEASE_LOAD_DRIVER_PATH"
    assert_includes workflow, "SCREENOTE_LOAD_DRIVER: ${{ github.workspace }}/script/self_hosted_load_driver"
    assert_not_includes workflow, "SCREENOTE_RELEASE_MINIMUM_HOST_PROFILE"
    assert_includes workflow, "SCREENOTE_PUBLIC_CLI_CONTRACT_PATH"
    assert_includes workflow, "script/release_test_matrix backup-restore"
    assert_includes workflow, "script/self_hosted_load_smoke"
    assert_includes workflow, "script/release_test_matrix public-cli"
    assert_includes workflow, "script/self_hosted_container_smoke"
    assert_includes workflow, 'database_directory="$RUNNER_TEMP/saas-databases-$suffix"'
    assert_includes workflow,
      "type=bind,source=$database_directory,target=/tmp/screenote-saas-databases"
    assert_includes workflow, '"${application_environment[@]}" "$QUALIFICATION_IMAGE" ./bin/rails db:prepare'
    assert_includes workflow, '"${application_environment[@]}" "$QUALIFICATION_IMAGE" >/dev/null'
    assert_not_includes workflow, "--entrypoint"
    assert_operator workflow.scan("--pull=never").length, :>=, 2
    %w[DATABASE_URL CACHE_DATABASE_URL QUEUE_DATABASE_URL CABLE_DATABASE_URL].each do |environment_key|
      assert_includes workflow, "--env #{environment_key}="
    end
    assert_includes workflow, "screenote-saas-image-qualification/v2"
    assert_includes workflow, "config&.respond_to?(:url) && config.url == expected_url"
    assert_includes workflow, "connection_handler.establish_connection(config, owner_name: connection_name)"
    assert_includes workflow, 'connection.select_value("SELECT 1").to_s == "1"'
    assert_includes workflow, "docker exec --interactive"
    assert_includes workflow, "SaaS installation identity does not match"
    assert_not_includes workflow.downcase, "postgres"
    assert_not_includes workflow, "server_version_num"
    assert_not_includes workflow, "adapter_name"
    matrix = Rails.root.join("script/release_test_matrix").read
    assert_includes matrix, "SCREENOTE_PUBLIC_CLI_TARGET"
    assert_includes matrix, "SCREENOTE_PUBLIC_CLI_EVIDENCE_PATH"
    assert_includes matrix, "wrong_ca_rejected"
    assert_includes matrix, "wrong_hostname_rejected"
    assert_includes workflow, "Validate each CLI transport evidence and create its redacted record"
    assert_includes workflow, '"qualification must contain exactly eight check records"'
  end

  test "release validator rejects adapter-specific qualification coupling" do
    Dir.mktmpdir("screenote-release-qualification") do |root|
      workflow_directory = File.join(root, ".github/workflows")
      FileUtils.mkdir_p(workflow_directory)
      Rails.root.glob(".github/workflows/*.{yml,yaml}").each do |workflow|
        FileUtils.cp(workflow, workflow_directory)
      end
      action_pins = File.join(root, "docs/releases/action-pins.md")
      FileUtils.mkdir_p(File.dirname(action_pins))
      FileUtils.cp(Rails.root.join("docs/releases/action-pins.md"), action_pins)
      File.open(File.join(workflow_directory, "release-qualification.yml"), "a") do |workflow|
        workflow.puts("# PostgreSQL-specific qualification regression")
      end

      validator = ReleaseValidation.new(root: root)
      validator.send(:workflow_contracts)

      assert_includes validator.errors,
        "qualification workflow must not couple SaaS boot evidence to a database adapter"
    end
  end

  test "SQLite load evidence is retained after verification and transitively hash bound" do
    qualification = YAML.safe_load(
      Rails.root.join(".github/workflows/release-qualification.yml").read,
      permitted_classes: [],
      aliases: false
    )
    jobs = qualification.fetch("jobs")
    minimum_host_steps = jobs.fetch("minimum-host").fetch("steps")
    verifier_index = minimum_host_steps.index do |step|
      step["name"] == "Run exact-image SQLite minimum-host load profile"
    end
    retention_index = minimum_host_steps.index do |step|
      step["name"] == "Retain verifier-approved redacted SQLite load evidence"
    end
    check_records = minimum_host_steps.find do |step|
      step["name"] == "Create redacted minimum-host check records"
    end

    assert_not_nil verifier_index
    assert_not_nil retention_index
    assert_operator verifier_index, :<, retention_index
    assert_equal 'script/self_hosted_load_smoke >"$RUNNER_TEMP/sqlite-load-evidence.json"',
      minimum_host_steps.fetch(verifier_index).fetch("run")
    retention = minimum_host_steps.fetch(retention_index).fetch("run")
    assert_includes retention, 'source="$RUNNER_TEMP/sqlite-load-evidence.json"'
    assert_includes retention, 'destination="$RUNNER_TEMP/checks/evidence/sqlite-load.json"'
    assert_includes retention, 'test ! -L "$source"'
    assert_includes retention, 'cp -- "$source" "$destination"'
    assert_includes check_records.fetch("run"),
      'load_evidence="$RUNNER_TEMP/checks/evidence/sqlite-load.json"'
    assert_includes check_records.fetch("run"),
      'if ENV.fetch("NAME") == "sqlite-load" && ENV.fetch("TARGET") == "minimum-host"'
    assert_includes check_records.fetch("run"),
      'record["load_evidence_sha256"] = ENV.fetch("LOAD_EVIDENCE_SHA256")'

    record = jobs.fetch("record").fetch("steps").find do |step|
      step["name"] == "Build one canonical redacted qualification record"
    end.fetch("run")
    assert_includes record, 'LOAD_EVIDENCE="$input/evidence/sqlite-load.json"'
    assert_includes record, 'OUTPUT_EVIDENCE="$output/checks/evidence/sqlite-load.json"'
    assert_includes record, 'expected_keys << "load_evidence_sha256" if sqlite_load'
    assert_includes record, "Digest::SHA256.file(load_evidence).hexdigest == load_evidence_sha256"
    assert_includes record, 'FileUtils.copy_file(load_evidence, ENV.fetch("OUTPUT_EVIDENCE"))'
    assert_includes record, 'check.slice("name", "target", "status").merge('

    release = YAML.safe_load(
      Rails.root.join(".github/workflows/release.yml").read,
      permitted_classes: [],
      aliases: false
    )
    authorization = release.fetch("jobs").fetch("authorize").fetch("steps").find do |step|
      step["name"] == "Verify exact qualification bytes and live CLI tag"
    end.fetch("run")
    assert_includes authorization, '"checks/evidence/sqlite-load.json"'
    assert_includes authorization,
      'expected["load_evidence_sha256"] = Digest::SHA256.file(load_evidence).hexdigest if sqlite_load'
    assert_includes authorization, 'abort "qualification check record identity does not match" unless record == expected'
  end

  test "public CLI qualification invokes and validates each transport independently" do
    Dir.mktmpdir("screenote-public-cli-qualification") do |directory|
      driver = File.join(directory, "driver")
      evidence_directory = File.join(directory, "evidence")
      call_log = File.join(directory, "calls")
      File.write(driver, <<~'RUBY')
        #!/usr/bin/env ruby
        require "json"

        target = ENV.fetch("SCREENOTE_PUBLIC_CLI_TARGET")
        evidence = {
          "schema" => "screenote-public-cli-qualification/v1",
          "status" => "passed",
          "target" => target,
          "origin" => ENV.fetch("SCREENOTE_PUBLIC_CLI_ORIGIN"),
          "candidate_image" => ENV.fetch("SCREENOTE_RELEASE_IMAGE"),
          "cli_tag" => ENV.fetch("SCREENOTE_PUBLIC_CLI_TAG"),
          "cli_sha" => ENV.fetch("SCREENOTE_PUBLIC_CLI_SHA"),
          "tls" => {
            "verified" => target == "https",
            "wrong_ca_rejected" => target == "https",
            "wrong_hostname_rejected" => target == "https"
          }
        }
        if target == "https"
          case ENV["SCREENOTE_TEST_CLI_MUTATION"]
          when "origin" then evidence["origin"] = "https://wrong.example.test"
          when "candidate" then evidence["candidate_image"] = "ghcr.io/example/wrong@sha256:#{'0' * 64}"
          when "tls" then evidence.fetch("tls")["wrong_ca_rejected"] = false
          end
        end
        File.open(ENV.fetch("SCREENOTE_TEST_CLI_CALL_LOG"), "a") { |file| file.puts(target) }
        File.binwrite(ENV.fetch("SCREENOTE_PUBLIC_CLI_EVIDENCE_PATH"), JSON.generate(evidence))
      RUBY
      FileUtils.chmod(0o700, driver)
      environment = {
        "SCREENOTE_PUBLIC_CLI_TAG" => "v1.2.3",
        "SCREENOTE_PUBLIC_CLI_SHA" => "a" * 40,
        "SCREENOTE_PUBLIC_CLI_CONTRACT_SCRIPT" => driver,
        "SCREENOTE_PUBLIC_CLI_HTTP_ORIGIN" => "http://127.0.0.1:3100",
        "SCREENOTE_PUBLIC_CLI_HTTPS_ORIGIN" => "https://127.0.0.1:3443",
        "SCREENOTE_PUBLIC_CLI_EVIDENCE_DIRECTORY" => evidence_directory,
        "SCREENOTE_RELEASE_IMAGE" => "ghcr.io/example/screenote@sha256:#{'b' * 64}",
        "SCREENOTE_TEST_CLI_CALL_LOG" => call_log
      }

      _stdout, stderr, status = Open3.capture3(
        environment,
        Rails.root.join("script/release_test_matrix").to_s,
        "public-cli"
      )
      assert status.success?, stderr
      assert_equal %w[http https], File.readlines(call_log, chomp: true)
      assert_equal %w[http.json https.json], Dir.children(evidence_directory).sort

      %w[origin candidate tls].each do |mutation|
        FileUtils.rm_rf(evidence_directory)
        FileUtils.rm_f(call_log)
        _stdout, stderr, status = Open3.capture3(
          environment.merge("SCREENOTE_TEST_CLI_MUTATION" => mutation),
          Rails.root.join("script/release_test_matrix").to_s,
          "public-cli"
        )
        assert_not status.success?, "#{mutation} evidence unexpectedly passed"
        assert_includes stderr, "https CLI evidence is invalid"
      end
    end
  end

  test "authorizing commit requires exact release evidence statuses" do
    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    source = release.fetch("jobs").fetch("authorize").fetch("steps").find do |step|
      step["id"] == "authorization-source"
    end.fetch("run")
    classifier = source.match(
      /AUTHORIZATION_CHANGES="\$authorization_changes" ruby <<'RUBY'\n(?<ruby>.*?)^RUBY$/m
    )&.named_captures&.fetch("ruby")
    assert_not_nil classifier

    expected = [
      "D", "docs/releases/PUBLICATION_BLOCKED.md",
      "A", "docs/releases/evidence/public-evidence.json",
      "M", "docs/releases/initial-release.md"
    ]
    _stdout, stderr, status = run_embedded_file_script(classifier, "AUTHORIZATION_CHANGES", expected.join("\0") << "\0")
    assert status.success?, stderr

    {
      "modified sentinel" => expected.dup.tap { |fields| fields[0] = "M" },
      "modified evidence" => expected.dup.tap { |fields| fields[2] = "M" },
      "added notes" => expected.dup.tap { |fields| fields[4] = "A" },
      "unexpected file" => expected + [ "A", "docs/releases/extra.md" ]
    }.each do |label, fields|
      _stdout, stderr, status = run_embedded_file_script(
        classifier,
        "AUTHORIZATION_CHANGES",
        fields.join("\0") << "\0"
      )
      assert_not status.success?, "#{label} unexpectedly passed"
      assert_includes stderr, "authorizing commit must exactly delete the sentinel, add evidence, and modify notes"
    end
  end

  test "candidate archive rejects unsafe paths and member types before extraction" do
    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    source = release.fetch("jobs").fetch("authorize").fetch("steps").find do |step|
      step["name"] == "Verify retained bytes and candidate metadata"
    end.fetch("run")
    start = source.index('CANDIDATE_ARCHIVE="$bundle" ruby -rrubygems/package')
    assert_not_nil start
    finish = source.index(%(\nCANDIDATE_SHA256="$CANDIDATE_SHA256" ruby <<'RUBY'), start)
    assert_not_nil finish
    archive_gate = source.byteslice(start...finish)

    Dir.mktmpdir("screenote-unsafe-candidate") do |root|
      fake_bin = File.join(root, "bin")
      FileUtils.mkdir_p(fake_bin)
      fake_tar = File.join(fake_bin, "tar")
      File.write(fake_tar, <<~BASH)
        #!/usr/bin/env bash
        set -euo pipefail
        test "$1" = -xf
        : > "$EXTRACTION_MARKER"
      BASH
      FileUtils.chmod(0o755, fake_tar)
      extraction_marker = File.join(root, "extraction-attempted")

      safe_archive = File.join(root, "safe.tar")
      write_tar_archive(safe_archive) do |tar|
        tar.mkdir("safe", 0o755)
        tar.add_file_simple("safe/file.txt", 0o644, 4) { |io| io.write("safe") }
      end
      _stdout, stderr, status = run_candidate_archive_gate(
        archive_gate, safe_archive, extraction_marker, fake_bin, root
      )
      assert status.success?, stderr
      assert File.exist?(extraction_marker), "safe archive did not reach extraction"

      unsafe_archives = {
        "traversal" => [ "unsafe candidate archive path", ->(tar) do
          tar.add_file_simple("../outside", 0o644, 1) { |io| io.write("x") }
        end ],
        "symlink" => [ "unsafe candidate archive member type", ->(tar) do
          tar.add_symlink("safe-link", "../outside", 0o777)
        end ]
      }
      unsafe_archives.each do |label, (expected_error, writer)|
        archive = File.join(root, "#{label}.tar")
        write_tar_archive(archive, &writer)
        FileUtils.rm_f(extraction_marker)
        _stdout, stderr, status = run_candidate_archive_gate(
          archive_gate, archive, extraction_marker, fake_bin, root
        )

        assert_not status.success?, "#{label} archive unexpectedly passed"
        assert_includes stderr, expected_error
        assert_not File.exist?(extraction_marker), "#{label} archive reached extraction"
      end
    end
  end

  test "protected-environment gate requires one exact approval for the current run" do
    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    approval_step = release.fetch("jobs").fetch("promotion").fetch("steps").first
    validator_source = approval_step.fetch("run").match(
      /APPROVALS_JSON="\$approvals_json" ruby -rjson <<'RUBY'\n(?<ruby>.*?)^RUBY$/m
    )&.named_captures&.fetch("ruby")
    assert_not_nil validator_source
    assert_nothing_raised do
      RubyVM::InstructionSequence.compile(validator_source, "release-current-run-approval-gate")
    end

    validator = %(require "json"\n#{validator_source})
    review = {
      "state" => "approved",
      "comment" => "Ship it!",
      "environments" => [
        { "id" => 161_088_068, "name" => "source-release", "created_at" => "2026-08-06T00:40:00Z" }
      ],
      "user" => { "login" => "octocat", "id" => 1 }
    }

    _stdout, stderr, status = run_embedded_file_script(
      validator, "APPROVALS_JSON", JSON.generate([ review ])
    )
    assert status.success?, stderr

    rejected_reviews = {
      "missing review" => [],
      "multiple reviews" => [ review, review ],
      "rejected review" => [ review.merge("state" => "rejected") ],
      "wrong environment" => [ review.merge("environments" => [ { "name" => "production" } ]) ],
      "multiple environments" => [
        review.merge("environments" => [ { "name" => "source-release" }, { "name" => "production" } ])
      ]
    }
    rejected_reviews.each do |label, reviews|
      _stdout, _stderr, status = run_embedded_file_script(
        validator, "APPROVALS_JSON", JSON.generate(reviews)
      )
      assert_not status.success?, "#{label} unexpectedly passed"
    end
    _stdout, _stderr, status = run_embedded_file_script(validator, "APPROVALS_JSON", "{")
    assert_not status.success?, "malformed current-run reviews unexpectedly passed"
  end

  test "registry image preflight accepts only exact absence responses" do
    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    preflight = release.fetch("jobs").fetch("promotion").fetch("steps").find { |step| step["id"] == "preflight" }
    source = preflight.fetch("run")
    classifier = source.match(
      /registry_not_found\(\) \{\n  local reference="\$1"\n  local error_file="\$2"\n  IMAGE_REFERENCE="\$reference" REGISTRY_ERROR="\$error_file" ruby <<'RUBY'\n(?<ruby>.*?)^RUBY\n\}/m
    )&.named_captures&.fetch("ruby")
    assert_not_nil classifier
    assert_equal 2, source.scan(/elif registry_not_found "\$IMAGE_REPOSITORY:(?:latest|\$RELEASE_TAG)" "\$(?:latest|remote)_error"; then/).length

    [
      "ghcr.io/ivankuznetsov/screenote:v1.0.0",
      "ghcr.io/ivankuznetsov/screenote:latest"
    ].each do |reference|
      accepted = [
        %(Error response from registry: failed to find "#{reference}": #{reference}: not found\n),
        "Error response from registry: manifest unknown: manifest unknown\n"
      ]
      accepted.each do |error|
        _stdout, stderr, status = run_embedded_file_script(
          classifier,
          "REGISTRY_ERROR",
          error,
          "IMAGE_REFERENCE" => reference
        )
        assert status.success?, stderr
      end

      rejected = {
        "bare not found" => "transport endpoint not found\n",
        "bare 404" => "proxy returned HTTP 404 Not Found\n",
        "unrelated code" => "Error response from registry: denied: MANIFEST_UNKNOWN\n",
        "ambiguous trailing error" => %(Error response from registry: failed to find "#{reference}": #{reference}: not found\nauthorization failed\n),
        "ambiguous manifest error" => "Error response from registry: manifest unknown: manifest unknown\nnetwork timeout\n",
        "contradictory manifest detail" => "Error response from registry: manifest unknown: backend timeout\n"
      }
      rejected.each do |label, error|
        _stdout, _stderr, status = run_embedded_file_script(
          classifier,
          "REGISTRY_ERROR",
          error,
          "IMAGE_REFERENCE" => reference
        )
        assert_not status.success?, "#{reference} #{label} unexpectedly passed"
      end
    end
  end

  test "GitHub remote preflight accepts only the exact 404 absence response" do
    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    preflight = release.fetch("jobs").fetch("promotion").fetch("steps").find { |step| step["id"] == "preflight" }
    source = preflight.fetch("run")
    classifier = source.match(
      /github_not_found\(\) \{\n  GITHUB_ERROR="\$1" ruby <<'RUBY'\n(?<ruby>.*?)^RUBY\n\}/m
    )&.named_captures&.fetch("ruby")
    assert_not_nil classifier
    assert_equal 2, source.scan(/elif github_not_found "\$(?:ref|release)_error"; then/).length
    assert_no_match(/grep -Eq .*HTTP 404\|Not Found/, source)

    _stdout, stderr, status = run_embedded_file_script(
      classifier,
      "GITHUB_ERROR",
      "gh: Not Found (HTTP 404)\n"
    )
    assert status.success?, stderr

    rejected = {
      "bare Not Found" => "Not Found\n",
      "wrong status" => "gh: Not Found (HTTP 500)\n",
      "Not Found plus 500" => "gh: Not Found (HTTP 404)\ngh: Internal Server Error (HTTP 500)\n",
      "Not Found plus backend error" => "gh: Not Found (HTTP 404)\nbackend timeout\n"
    }
    rejected.each do |label, error|
      _stdout, _stderr, status = run_embedded_file_script(classifier, "GITHUB_ERROR", error)
      assert_not status.success?, "#{label} unexpectedly passed"
    end
  end

  test "release preflight never lets an older release move latest backwards" do
    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    preflight = release.fetch("jobs").fetch("promotion").fetch("steps").find { |step| step["id"] == "preflight" }
    source = preflight.fetch("run")
    guard = source.match(
      /PUBLISHED_RELEASES_JSON="\$published_releases" ruby -rjson <<'RUBY'\n(?<ruby>.*?)^RUBY$/m
    )&.named_captures&.fetch("ruby")
    assert_not_nil guard

    run_guard = lambda do |releases, release_tag, predecessor_tag|
      Tempfile.create([ "published-releases", ".json" ]) do |file|
        file.write(JSON.generate([ releases ]))
        file.flush
        Open3.capture3(
          {
            "PREDECESSOR_TAG" => predecessor_tag,
            "PUBLISHED_RELEASES_JSON" => file.path,
            "RELEASE_TAG" => release_tag
          },
          RbConfig.ruby,
          "-rjson",
          "-e",
          guard
        )
      end
    end

    current = { "tag_name" => "v1.2.3", "draft" => false, "prerelease" => false, "immutable" => true }
    ignored = [
      { "tag_name" => "v9.0.0", "draft" => true, "prerelease" => false, "immutable" => false },
      { "tag_name" => "v8.0.0", "draft" => false, "prerelease" => true, "immutable" => false }
    ]
    _stdout, stderr, status = run_guard.call([ current, *ignored ], "v1.2.3", "none")
    assert status.success?, stderr

    predecessor = { "tag_name" => "v1.2.2", "draft" => false, "prerelease" => false, "immutable" => true }
    _stdout, stderr, status = run_guard.call([ predecessor ], "v1.2.3", "v1.2.2")
    assert status.success?, stderr
    _stdout, stderr, status = run_guard.call([ current, predecessor ], "v1.2.3", "v1.2.2")
    assert status.success?, stderr

    _stdout, stderr, status = run_guard.call([ predecessor ], "v1.2.3", "v1.2.1")
    assert_not status.success?
    assert_includes stderr, "newest published stable release does not match the recorded predecessor"

    _stdout, stderr, status = run_guard.call([ current ], "v1.2.2", "none")
    assert_not status.success?
    assert_includes stderr, "a newer GitHub Release already exists"

    mutable = predecessor.merge("immutable" => false)
    _stdout, stderr, status = run_guard.call([ mutable ], "v1.2.3", "v1.2.2")
    assert_not status.success?
    assert_includes stderr, "published stable release is not immutable"

    _stdout, stderr, status = run_guard.call([ predecessor ], "v1.2.3", "none")
    assert_not status.success?
    assert_includes stderr, "first release cannot have a published stable predecessor"
  end

  test "release workflow builds before mutation and uses checksum-pinned scanners" do
    workflow = Rails.root.join(".github/workflows/release.yml").read
    parsed = YAML.safe_load(workflow, permitted_classes: [], aliases: false)
    promotion = parsed.fetch("jobs").fetch("promotion")
    assert_equal "source-release-${{ inputs.operation == 'publish' && 'promotion' || inputs.release_tag }}",
      parsed.dig("concurrency", "group")
    authorize_steps = parsed.fetch("jobs").fetch("authorize").fetch("steps")
    assert_equal "${{ steps.verify.outputs.predecessor_image_digest }}",
      parsed.dig("jobs", "authorize", "outputs", "predecessor_image_digest")
    assert_equal "${{ steps.verify.outputs.predecessor_tag }}",
      parsed.dig("jobs", "authorize", "outputs", "predecessor_tag")
    steps = promotion.fetch("steps")
    approval_index = steps.index { |step| step["id"] == "current-run-approval" }
    live_index = steps.index { |step| step["id"] == "live-incidents" }
    preflight_index = steps.index { |step| step["id"] == "preflight" }
    preflight = steps.fetch(preflight_index)
    image_index = steps.index { |step| step.fetch("run", "").include?("oras cp --from-oci-layout") }
    tag_index = steps.index { |step| step.fetch("run", "").include?('gh api --method POST "/repos/$GITHUB_REPOSITORY/git/refs"') }
    attestation_index = steps.index { |step| step.fetch("uses", "").start_with?("actions/attest@") }
    release_index = steps.index { |step| step.fetch("run", "").include?('gh release create "$RELEASE_TAG"') }
    newest_release_index = steps.index { |step| step["name"] == "Verify the newest immutable GitHub release" }
    latest_image_index = steps.index { |step| step.fetch("run", "").include?('oras tag "$IMAGE_REPOSITORY@$MANIFEST_DIGEST" latest') }
    final_index = steps.index { |step| step["name"] == "Verify every published object" }
    verify_candidate_index = authorize_steps.index { |step| step["name"] == "Verify retained bytes and candidate metadata" }
    final_scan_index = authorize_steps.index { |step| step["name"] == "Scan exact authorizing release bytes" }
    retain_verified_index = authorize_steps.index { |step| step["name"] == "Retain only the verified promotion input" }

    assert_equal 0, approval_index
    assert_equal 1, live_index
    assert_operator approval_index, :<, live_index
    assert_operator live_index, :<, preflight_index
    approval_step = steps.fetch(approval_index)
    assert_equal "${{ github.token }}", approval_step.dig("env", "GH_TOKEN")
    assert_nil approval_step.dig("env", "WORKFLOW_RUN_ID")
    assert_nil approval_step.dig("env", "WORKFLOW_RUN_ATTEMPT")
    assert_includes approval_step.fetch("run"), "current workflow run must have exactly one environment review"
    assert_includes approval_step.fetch("run"), "current workflow run approval must cover exactly source-release"
    assert_includes approval_step.fetch("run"), "gh api --method GET"
    assert_includes approval_step.fetch("run"), '"/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/approvals"'
    assert_not_includes approval_step.fetch("run"), "File.binwrite"
    assert_not_includes approval_step.fetch("run"), "Digest"
    live_step = steps.fetch(live_index)
    assert_equal "ruby {0}", live_step.fetch("shell")
    assert_equal "${{ secrets.GITGUARDIAN_INCIDENTS_API_KEY }}", live_step.dig("env", "GITGUARDIAN_API_KEY")
    assert_includes live_step.fetch("run"), "/incidents/secrets"
    assert_includes live_step.fetch("run"), "TRIGGERED"
    assert_includes live_step.fetch("run"), "ASSIGNED"
    assert_includes live_step.fetch("run"), 'provider_metadata["archived"] == false'
    assert_includes live_step.fetch("run"), 'source["deleted"] == false'
    [ image_index, tag_index, attestation_index, release_index, latest_image_index ].each do |mutation_index|
      assert_operator preflight_index, :<, mutation_index
      assert_operator mutation_index, :<, final_index
    end
    assert_operator release_index, :<, newest_release_index
    assert_operator newest_release_index, :<, latest_image_index
    preflight_source = preflight.fetch("run")
    release_token = steps.find { |step| step["id"] == "release-token" }
    assert_equal "read", release_token.dig("with", "permission-administration")
    assert_nil preflight.dig("env", "ACTIONS_TOKEN")
    assert_nil preflight.dig("env", "EXPECTED_DEFAULT_BRANCH")
    assert_equal "${{ needs.authorize.outputs.predecessor_image_digest }}",
      preflight.dig("env", "PREDECESSOR_IMAGE_DIGEST")
    assert_equal "${{ needs.authorize.outputs.predecessor_tag }}",
      preflight.dig("env", "PREDECESSOR_TAG")
    assert_includes preflight_source, '"/repos/$GITHUB_REPOSITORY/immutable-releases"'
    assert_includes preflight_source, "X-GitHub-Api-Version: 2026-03-10"
    assert_includes preflight_source, 'status["enabled"] == true'
    assert_includes preflight_source, "status.keys.sort == exact_keys"
    assert_includes preflight_source, "oras manifest fetch --descriptor"
    assert_includes preflight_source, "/git/ref/tags/"
    assert_includes preflight_source, "/attestations/sha256:"
    assert_includes preflight_source, "/releases/tags/"
    assert_includes preflight_source, '"/repos/$GITHUB_REPOSITORY/releases?per_page=100"'
    assert_includes preflight_source, "a newer GitHub Release already exists"
    assert_includes preflight_source, "published stable release is not immutable"
    assert_includes preflight_source, "newest published stable release does not match the recorded predecessor"
    assert_includes preflight_source, 'oras resolve "$IMAGE_REPOSITORY:$PREDECESSOR_TAG"'
    assert_includes preflight_source, 'oras manifest fetch --descriptor "$IMAGE_REPOSITORY:latest"'
    assert_includes preflight_source, 'test "$latest_digest" = "$MANIFEST_DIGEST"'
    assert_includes preflight_source, 'test "$latest_digest" = "$PREDECESSOR_IMAGE_DIGEST"'
    assert_includes preflight_source, "latest_state=candidate"
    assert_includes preflight_source, "latest_state=predecessor"
    assert_includes preflight_source, "latest_state=absent"
    assert_includes preflight_source, "Latest image is absent for a successor release"
    assert_includes preflight_source, "Current latest manifest is neither this release nor its recorded predecessor"
    assert_not_includes preflight_source, "/actions/runs/"
    assert_not_includes preflight_source, "/releases/assets/"
    assert_includes preflight_source, "publication_state=\"$image_state:$tag_state:$attestation_state:$release_state\""
    assert_includes preflight_source, "exact:exact:exact:exact"
    assert_not_includes preflight_source, "oras cp --from-oci-layout"
    assert_not_includes preflight_source, "gh api --method POST"
    assert_not_includes preflight_source, "gh release create"
    assert_equal "steps.preflight.outputs.image_state == 'absent'", steps.fetch(image_index).fetch("if")
    assert_equal "steps.preflight.outputs.tag_state == 'absent'", steps.fetch(tag_index).fetch("if")
    assert_equal "steps.preflight.outputs.attestation_state == 'absent'", steps.fetch(attestation_index).fetch("if")
    assert_equal "steps.preflight.outputs.release_state == 'absent'", steps.fetch(release_index).fetch("if")
    assert_includes steps.fetch(release_index).fetch("run"), "--latest"
    newest_release = steps.fetch(newest_release_index).fetch("run")
    assert_includes newest_release, '"/repos/$GITHUB_REPOSITORY/releases/latest"'
    assert_includes newest_release, 'release["tag_name"] == ENV.fetch("RELEASE_TAG")'
    assert_includes newest_release, 'release["immutable"] == true'
    assert_includes newest_release, 'gh release verify "$RELEASE_TAG"'
    latest_image = steps.fetch(latest_image_index).fetch("run")
    assert_includes latest_image, 'oras tag "$IMAGE_REPOSITORY@$MANIFEST_DIGEST" latest'
    assert_includes latest_image, 'oras resolve "$IMAGE_REPOSITORY:latest"'
    final_verification = steps.fetch(final_index).fetch("run")
    assert_includes final_verification, 'oras resolve "$IMAGE_REPOSITORY:latest"'
    assert_includes final_verification, "git/ref/tags/$RELEASE_TAG"
    assert_includes final_verification, "gh attestation verify"
    assert_not_includes final_verification, "/releases/tags/$RELEASE_TAG"
    assert_not_includes final_verification, "release notes do not match"
    assert_not_includes final_verification, "expected_assets"
    assert_not_includes final_verification, 'gh release verify "$RELEASE_TAG"'
    assert_not_includes workflow, "environment-approval.json"
    assert_not_includes workflow, "historical-environment-approval"

    assert_operator verify_candidate_index, :<, final_scan_index
    assert_includes authorize_steps.fetch(verify_candidate_index).fetch("run"),
      'echo "predecessor_tag=$(ruby -rjson'
    assert_operator final_scan_index, :<, retain_verified_index
    final_scan = authorize_steps.fetch(final_scan_index)
    assert_equal "${{ secrets.GITGUARDIAN_API_KEY }}", final_scan.dig("env", "GITGUARDIAN_API_KEY")
    assert_equal "1", final_scan.dig("env", "GITGUARDIAN_DONT_LOAD_ENV")
    assert_includes final_scan.fetch("run"), '"$RUNNER_TEMP/verified/release-notes.md"'
    assert_includes final_scan.fetch("run"), '"$RUNNER_TEMP/verified/public-evidence.json"'
    ggshield_prefix = 'ggshield --config-path "$GITHUB_WORKSPACE/.gitguardian.yaml" secret scan'
    assert_includes final_scan.fetch("run"), "#{ggshield_prefix} path --yes --all-secrets"
    assert_equal "https://dashboard.gitguardian.com", final_scan.dig("env", "GITGUARDIAN_INSTANCE")
    assert_not_includes final_scan.fetch("run"), "--ignore-known-secrets"

    assert_operator workflow.index("docker buildx build"), :<, workflow.index("oras cp --from-oci-layout")
    assert_operator workflow.index("--mode publish"), :<, workflow.index("oras cp --from-oci-layout")
    assert_includes workflow, "#{ggshield_prefix} repo ."
    assert_includes workflow, "#{ggshield_prefix} path --recursive --yes --all-secrets ."
    assert_includes workflow, "#{ggshield_prefix} docker"
    assert_equal 3, workflow.scan("GITGUARDIAN_INSTANCE: https://dashboard.gitguardian.com").length
    assert_includes workflow, "TRIVY_VERSION: 0.70.0"
    assert_includes workflow, "--exit-code 1"
    assert_includes workflow, '--config "$RUNNER_TEMP/trivy-release.yaml"'
    assert_includes workflow, '--ignorefile "$RUNNER_TEMP/trivy-release.ignore"'
    assert_includes workflow, "--show-suppressed"
    assert_includes workflow, 'report["SchemaVersion"] == 2'
    assert_includes workflow, 'results = report["Results"]'
    assert_not_includes workflow, 'fetch("Results", [])'
    assert_not_includes workflow, 'fetch("Vulnerabilities", [])'
    assert_includes workflow, "SYFT_VERSION: 1.44.0"
    assert_includes workflow, '--config "$RUNNER_TEMP/syft-release.yaml"'
    assert_includes workflow, "ORAS_VERSION: 1.3.2"
    assert_includes workflow, "sha256sum --check --strict"
    assert_includes workflow, "promotion-does-not-checkout"
    assert_includes workflow, "Create GitHub provenance attestation"
    assert_includes workflow, "https://screenote.ai/attestations/release-provenance/v1"
    assert_includes workflow, "predicate-path: ${{ runner.temp }}/promotion/provenance.json"
    assert_includes workflow, '--source-digest "$AUTHORIZING_SHA"'
    assert_includes workflow, 'statement["predicate"] == expected_predicate'
    assert_includes workflow, 'release["immutable"] == true'
    assert_includes workflow, 'release["name"] == "Screenote #{ENV.fetch(\'RELEASE_TAG\')}"'
    assert_includes workflow, 'gh release verify "$RELEASE_TAG"'
    assert_not_includes workflow, '--source-digest "$SOURCE_SHA"'
    assert_not_includes workflow, "continue-on-error: true"
    assert_not_includes workflow, "--ignore-known-secrets"
    validator = Rails.root.join("bin/release-validate").read
    assert_includes validator, "tracked scanner auto-configuration paths remain"
    %w[.trivyignore trivy.yaml .syft.yaml .syft/config.yaml].each do |autoconfig|
      assert_includes validator, autoconfig
    end

    dockerfile = Rails.root.join("Dockerfile").read
    assert_equal [ BASE_IMAGE, "base", "base" ], dockerfile.scan(/^FROM\s+(\S+)/).flatten
    assert_equal "ruby-3.4.10\n", Rails.root.join(".ruby-version").read
    %w[/go.mod /go.sum /cmd/ /internal/ /vendor/bundle/].each do |runtime_exclusion|
      assert_includes Rails.root.join(".dockerignore").read.lines.map(&:strip), runtime_exclusion
    end
    %w[source revision version description licenses].each do |label|
      assert_includes dockerfile, "org.opencontainers.image.#{label}"
    end
    assert_includes dockerfile, 'LABEL service="screenote"'
    assert_includes workflow, '"service" => "screenote"'
    assert_includes dockerfile, "LicenseRef-OSaasy"
  end

  test "immutable release setting fixtures fail closed before publication" do
    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    steps = release.fetch("jobs").fetch("promotion").fetch("steps")
    preflight = steps.find { |step| step["id"] == "preflight" }
    source = preflight.fetch("run")
    validator = source.match(
      /IMMUTABLE_RELEASES_JSON="\$immutable_releases" ruby -rjson <<'RUBY'\n(?<ruby>.*?)^RUBY$/m
    )&.named_captures&.fetch("ruby")
    assert_not_nil validator

    fixtures = Rails.root.join("test/fixtures/releases/immutable_releases")
    enabled = fixtures.join("enabled.json")
    _stdout, stderr, status = Open3.capture3(
      { "IMMUTABLE_RELEASES_JSON" => enabled.to_s },
      RbConfig.ruby,
      "-rjson",
      "-e",
      validator
    )
    assert status.success?, stderr

    %w[disabled unknown].each do |name|
      path = fixtures.join("#{name}.json")
      _stdout, stderr, status = Open3.capture3(
        { "IMMUTABLE_RELEASES_JSON" => path.to_s },
        RbConfig.ruby,
        "-rjson",
        "-e",
        validator
      )
      assert_not status.success?, "#{name} immutable-release state unexpectedly passed"
      assert_includes stderr, "immutable GitHub releases are not explicitly enabled"
    end

    preflight_index = steps.index(preflight)
    mutation_indexes = steps.each_index.select do |index|
      step = steps.fetch(index)
      step.fetch("run", "").match?(/oras cp --from-oci-layout|git\/refs|gh release create/) ||
        step.fetch("uses", "").start_with?("actions/attest@")
    end
    assert_predicate mutation_indexes, :any?
    mutation_indexes.each { |index| assert_operator preflight_index, :<, index }
  end

  test "container smoke tests a supplied release image without rebuilding it" do
    smoke = Rails.root.join("script/self_hosted_container_smoke").read
    backup_smoke = Rails.root.join("script/self_hosted_backup_smoke").read

    assert_match(/if \[\[ "\$\{REMOVE_IMAGE\}" == true \]\]; then.*docker build.*else.*docker image inspect/m, smoke)
    assert_includes Rails.root.join("script/release_test_matrix").read,
      'SCREENOTE_SMOKE_IMAGE="${SCREENOTE_RELEASE_IMAGE}" script/self_hosted_container_smoke'
    assert_equal 3, smoke.scan("exec -T screenote sqlite3").length
    assert_includes backup_smoke,
      "exec -T screenote /rails/bin/docker-entrypoint ./bin/rails runner -"
    assert_not_includes smoke, "--no-tty"
    assert_not_includes backup_smoke, "--no-tty"
    assert_not_includes smoke, "bootstrap_token"
    assert_not_includes backup_smoke, "bootstrap_token"
  end

  test "repository Go checks ignore the Rails vendor directory" do
    workflow = YAML.safe_load(
      Rails.root.join(".github/workflows/ci.yml").read,
      permitted_classes: [],
      aliases: false
    )
    step = workflow.fetch("jobs").fetch("public-cli").fetch("steps").find do |candidate|
      candidate["name"] == "Test repository Go compatibility helpers"
    end

    assert_not_nil step
    assert_equal "env GOFLAGS=-mod=mod go test ./...", step.fetch("run")
  end

  test "focused Rails CI jobs install the image runtime before Rails boots" do
    workflow = YAML.safe_load(
      Rails.root.join(".github/workflows/ci.yml").read,
      permitted_classes: [],
      aliases: false
    )
    %w[backup-restore public-cli release-artifact].each do |job|
      steps = workflow.fetch("jobs").fetch(job).fetch("steps")
      runtime = steps.find { |step| step.fetch("run", "").include?("libvips") }
      setup = steps.find { |step| step["name"] == "Set up Ruby" }

      assert_not_nil runtime, job
      assert_not_nil setup, job
      assert_operator steps.index(runtime), :<, steps.index(setup), job
    end

    browser_steps = workflow.fetch("jobs").fetch("system-collaboration").fetch("steps")
    playwright = browser_steps.find { |step| step["name"] == "Install Playwright Chromium" }
    assert_includes playwright.fetch("run"), "bundle exec ruby"
  end

  test "coverage CI budget accommodates both complete edition suites" do
    workflow = YAML.safe_load(
      Rails.root.join(".github/workflows/ci.yml").read,
      permitted_classes: [],
      aliases: false
    )
    coverage = workflow.fetch("jobs").fetch("coverage")
    gate = coverage.fetch("steps").find { |step| step["name"]&.include?("changed-security coverage") }

    assert_operator coverage.fetch("timeout-minutes"), :>=, 45
    assert_equal "script/release_test_matrix coverage", gate.fetch("run")
    assert_equal "${{ github.event_name == 'pull_request' && github.event.pull_request.base.sha || github.event.before }}",
      gate.dig("env", "SCREENOTE_COVERAGE_BASE_SHA")
  end

  test "source CI has one adapter-neutral test job and matching required checks" do
    workflow = YAML.safe_load(
      Rails.root.join(".github/workflows/ci.yml").read,
      permitted_classes: [],
      aliases: false
    )
    jobs = workflow.fetch("jobs")
    test_job = jobs.fetch("test")

    assert_equal "test", test_job.fetch("name")
    assert_not jobs.key?("sqlite")
    assert_not jobs.key?("postgresql")
    assert_equal "4", test_job.dig("env", "PARALLEL_WORKERS")
    assert_not test_job.fetch("env").key?("SCREENOTE_EDITION")
    assert_not test_job.fetch("env").key?("SCREENOTE_REQUIRED_MODE")
    assert_not test_job.fetch("env").key?("SCREENOTE_BOOTSTRAP_TOKEN")
    assert_not jobs.fetch("system-collaboration").fetch("env").key?("SCREENOTE_BOOTSTRAP_TOKEN")
    assert_includes test_job.fetch("steps").map { |step| step.fetch("run", "") }, "bin/rails test"
    steps = test_job.fetch("steps")
    runtime = steps.find { |step| step.fetch("run", "").include?("libvips") }
    setup = steps.find { |step| step["name"] == "Set up Ruby" }
    focused = steps.find { |step| step["name"] == "Run self-hosted edition-only tests" }

    assert_not_nil runtime
    assert_not_nil setup
    assert_not_nil focused
    assert_operator steps.index(runtime), :<, steps.index(setup)
    assert_equal "self_hosted", focused.dig("env", "SCREENOTE_EDITION")
    assert_equal "self_hosted", focused.dig("env", "SCREENOTE_REQUIRED_MODE")
    assert_includes focused.fetch("run"),
      "test/controllers/oauth/self_hosted_registrations_controller_test.rb"
    assert_includes focused.fetch("run"), "test/integration/self_hosted_full_flow_test.rb"

    ruleset = JSON.parse(Rails.root.join(".github/rulesets/main.json").read)
    checks = ruleset.fetch("rules").find do |rule|
      rule.fetch("type") == "required_status_checks"
    end.fetch("parameters").fetch("required_status_checks")
    contexts = checks.filter_map do |check|
      check.fetch("context") if check.fetch("context").start_with?("CI / ")
    end

    assert_equal ReleaseValidation::REQUIRED_CHECKS.map { |name| "CI / #{name}" }.sort,
      contexts.sort
  end

  test "self-hosted coverage is an explicit positive manifest with fail-closed drift detection" do
    manifest = YAML.safe_load(
      Rails.root.join("test/manifests/self_hosted.yml").read,
      permitted_classes: [],
      aliases: false
    )
    expected_capabilities = %w[
      edition_boundary
      boot_admission_admin
      shared_core_http_rest
      oauth_mcp_agent
      security_runtime
      operator_fast
    ]

    assert_equal 1, manifest.fetch("version")
    assert_equal expected_capabilities, manifest.fetch("capabilities").keys
    assert_equal %w[s3 system_claimed system_unclaimed], manifest.fetch("specialized").keys.sort

    groups = manifest.fetch("capabilities").merge(manifest.fetch("specialized"))
    groups.each do |name, paths|
      assert_predicate paths, :any?, name
      assert_equal paths.sort, paths, name
      paths.each { |path| assert_path_exists Rails.root.join(path), path }
    end

    manifest_tests = groups.values.flatten
    assert_equal manifest_tests.uniq, manifest_tests

    marked_tests = Rails.root.glob("test/**/*_test.rb").filter_map do |path|
      path.relative_path_from(Rails.root).to_s if path.readlines.any? do |line|
        line.chomp == "# screenote-edition: self_hosted"
      end
    end
    assert_equal manifest_tests.sort, marked_tests.sort

    convention_tests = Rails.root.glob("test/**/*_test.rb").filter_map do |path|
      contents = path.read
      if path.basename.to_s.start_with?("self_hosted_") ||
          contents.match?(/require_deployment_mode!\(\s*:self_hosted\s*\)/)
        path.relative_path_from(Rails.root).to_s
      end
    end
    assert_empty convention_tests - manifest_tests

    saas_only = manifest.fetch("saas_only")
    assert_equal saas_only.sort, saas_only
    assert_equal saas_only.uniq, saas_only
    assert_empty manifest_tests & saas_only
    saas_only.each { |path| assert_path_exists Rails.root.join(path), path }

    matrix = Rails.root.join("script/release_test_matrix").read
    assert_equal 2, matrix.scan("read_self_hosted_manifest_group self_hosted self_hosted_tests").length
    assert_includes matrix, 'bin/rails test "${self_hosted_tests[@]}"'
    assert_includes matrix, "self-hosted marker union does not equal the manifest"
    assert_includes matrix, "self-hosted convention tests are absent from the manifest"
    assert_includes matrix, "assert_mode_booted"
    assert_includes matrix, "SCREENOTE_DEFER_COVERAGE_GATE=1 TEST_ENV_NUMBER=1"
    assert_includes matrix, "SCREENOTE_DEFER_COVERAGE_GATE=1 TEST_ENV_NUMBER=2"
    assert_equal 2, matrix.scan("DISABLE_BOOTSNAP_COMPILE_CACHE=1").length
    assert_includes matrix, "test/support/coverage_boot"
    assert_includes matrix, "require_value SCREENOTE_COVERAGE_BASE_SHA"
    assert_includes matrix, '[[ "${SCREENOTE_COVERAGE_BASE_SHA}" =~ ^[0-9a-f]{40}$ ]]'
    assert_includes matrix, 'git cat-file -e "${SCREENOTE_COVERAGE_BASE_SHA}^{commit}"'
    assert_includes matrix, 'git merge-base --is-ancestor "${SCREENOTE_COVERAGE_BASE_SHA}" HEAD'
    assert_includes matrix, '--base "${SCREENOTE_COVERAGE_BASE_SHA}"'
    assert_includes matrix,
      "SCREENOTE_COVERAGE_BASE_SHA=<full-ancestor-sha> script/release_test_matrix coverage"
    assert_not_includes matrix, "git merge-base HEAD origin/main"
    assert_includes matrix, "--manifest test/manifests/release_security_coverage.yml"
    assert_not_includes matrix, "SCREENOTE_BOOTSTRAP_TOKEN"
    system_gate = matrix.match(/^  system-collaboration\).*?^    ;;$/m).to_s
    assert_not_empty system_gate
    assert_includes system_gate, "clobber_precompiled_assets"
    assert_operator system_gate.index("clobber_precompiled_assets"), :<,
      system_gate.index('bin/rails test "${system_unclaimed_tests[@]}"')
    full_suite_function = matrix.match(/^run_mode_suite\(\) \{.*?^\}/m).to_s
    assert_not_empty full_suite_function
    assert_not_includes full_suite_function, 'SCREENOTE_REQUIRED_MODE="${mode}"'
    assert_includes full_suite_function, "env -u SCREENOTE_REQUIRED_MODE"

    security_manifest = YAML.safe_load(
      Rails.root.join("test/manifests/release_security_coverage.yml").read,
      permitted_classes: [],
      aliases: false
    )
    assert_equal %w[version discovery domains], security_manifest.keys
    assert_equal 1, security_manifest.fetch("version")
    discovery = security_manifest.fetch("discovery")
    assert_predicate discovery, :any?
    assert_equal discovery.sort, discovery
    assert_equal %w[deployment bootstrap invitation principal suspension recovery transfer],
      security_manifest.fetch("domains").keys
    security_paths = security_manifest.fetch("domains").flat_map do |domain, paths|
      assert_predicate paths, :any?, domain
      assert_equal paths.sort, paths, domain
      paths.each { |path| assert_path_exists Rails.root.join(path), path }
      paths
    end
    assert_equal security_paths.uniq, security_paths
  end

  test "embedded workflow Ruby parses independently of YAML and shell linting" do
    release = YAML.safe_load(Rails.root.join(".github/workflows/release.yml").read, permitted_classes: [], aliases: false)
    run_blocks = release.fetch("jobs").values.flat_map do |job|
      job.fetch("steps", []).filter_map { |step| step["run"] }
    end
    ruby_blocks = run_blocks.flat_map do |run|
      run.scan(/ruby(?:\s+[^\n]*)?\s+<<'RUBY'\n(.*?)^RUBY$/m).flatten
    end

    assert_equal 16, ruby_blocks.length
    ruby_blocks.each_with_index do |source, index|
      assert_nothing_raised { RubyVM::InstructionSequence.compile(source, "release-workflow-ruby-#{index + 1}") }
    end

    qualification = YAML.safe_load(
      Rails.root.join(".github/workflows/release-qualification.yml").read,
      permitted_classes: [],
      aliases: false
    )
    qualification_ruby_blocks = qualification.fetch("jobs").values.flat_map do |job|
      job.fetch("steps", []).filter_map { |step| step["run"] }
    end.flat_map do |run|
      run.scan(/ruby(?:\s+[^\n]*)?\s+<<'RUBY'\n(.*?)^RUBY$/m).flatten
    end
    assert_equal 4, qualification_ruby_blocks.length
    qualification_ruby_blocks.each_with_index do |source, index|
      assert_nothing_raised do
        RubyVM::InstructionSequence.compile(source, "qualification-workflow-ruby-#{index + 1}")
      end
    end

    live_source = release.fetch("jobs").fetch("promotion").fetch("steps").find do |step|
      step["id"] == "live-incidents"
    end.fetch("run")
    assert_nothing_raised { RubyVM::InstructionSequence.compile(live_source, "release-live-incident-gate") }

    release.fetch("jobs").each do |job_name, job|
      job.fetch("steps", []).each_with_index do |step, index|
        next unless step["run"]
        next if step.fetch("shell", "bash").start_with?("ruby")

        Tempfile.create([ "release-workflow-shell", ".bash" ]) do |file|
          file.write(step.fetch("run"))
          file.flush
          _stdout, stderr, status = Open3.capture3("bash", "-n", file.path)
          assert status.success?, "#{job_name} step #{index + 1} shell syntax failed: #{stderr}"
        end
      end
    end

    secrets = YAML.safe_load(Rails.root.join(".github/workflows/secrets.yml").read, permitted_classes: [], aliases: false)
    incident_source = secrets.fetch("jobs").fetch("repository-incidents").fetch("steps").fetch(0).fetch("run")
    assert_nothing_raised { RubyVM::InstructionSequence.compile(incident_source, "secrets-workflow-ruby") }
  end

  private

  def evidence
    JSON.parse(EVIDENCE_FIXTURE.read)
  end

  def with_public_positioning_copy
    Dir.mktmpdir("screenote-public-positioning") do |root|
      ([ "README.md", *ReleaseValidation::SOURCE_BOUNDARY_FILES,
        *ReleaseValidation::PUBLIC_INSTALLATION_DOCS ]).uniq.each do |relative|
        destination = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(Rails.root.join(relative), destination)
      end
      yield root
    end
  end

  def validate_public_positioning(root)
    ReleaseValidation.new(root: root).tap { |validator| validator.send(:public_positioning) }
  end

  def assert_rejected(label, expected_error)
    mutated = evidence
    yield mutated

    Tempfile.create([ "screenote-release-evidence", ".json" ]) do |file|
      file.write(JSON.generate(mutated))
      file.flush
      _stdout, stderr, status = run_evidence(file.path)

      assert_not status.success?, "#{label} unexpectedly passed"
      assert_includes stderr, expected_error, label
    end
  end

  def run_evidence(path)
    run_validator(
      "--mode", "evidence",
      "--evidence", path.to_s,
      "--source-sha", SOURCE_SHA,
      "--tag", RELEASE_TAG,
      "--now", VALIDATION_TIME
    )
  end

  def run_validator(*arguments)
    Open3.capture3(RbConfig.ruby, VALIDATOR.to_s, *arguments, chdir: Rails.root.to_s)
  end

  def run_embedded_file_script(source, variable, contents, environment = {})
    Tempfile.create([ "screenote-release-script", ".bin" ]) do |file|
      file.binmode
      file.write(contents)
      file.flush
      Open3.capture3(environment.merge(variable => file.path), RbConfig.ruby, "-e", source)
    end
  end

  def run_head_resolution_validator(source, ref, commit)
    Tempfile.create([ "screenote-default-ref", ".json" ]) do |ref_file|
      Tempfile.create([ "screenote-default-commit", ".json" ]) do |commit_file|
        ref_file.write(JSON.generate(ref))
        ref_file.flush
        commit_file.write(JSON.generate(commit))
        commit_file.flush
        Open3.capture3(
          {
            "DEFAULT_BRANCH" => "main",
            "DEFAULT_COMMIT_JSON" => commit_file.path,
            "DEFAULT_REF_JSON" => ref_file.path,
            "EXPECTED_SHA" => SOURCE_SHA
          },
          RbConfig.ruby,
          "-rjson",
          "-e",
          source
        )
      end
    end
  end

  def run_candidate_workflow_identity_validator(source, run, environment)
    Open3.capture3(
      environment.merge("RUN_JSON" => JSON.generate(run)),
      RbConfig.ruby,
      "-rjson",
      "-e",
      source
    )
  end

  def write_tar_archive(path)
    File.open(path, "wb") do |file|
      Gem::Package::TarWriter.new(file) { |tar| yield tar }
    end
  end

  def run_candidate_archive_gate(archive_gate, archive, extraction_marker, fake_bin, runner_temp)
    script = <<~BASH
      set -euo pipefail
      bundle="$CANDIDATE_BUNDLE"
      #{archive_gate}
    BASH
    Open3.capture3(
      {
        "CANDIDATE_BUNDLE" => archive,
        "EXTRACTION_MARKER" => extraction_marker,
        "PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}",
        "RUNNER_TEMP" => runner_temp
      },
      "bash",
      "-c",
      script
    )
  end
end
