# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

class CoverageGateContractTest < ActiveSupport::TestCase
  COVERAGE_BOOT = Rails.root.join("test/support/coverage_boot.rb").freeze
  CHECKER = Rails.root.join("bin/check_coverage").freeze
  MATRIX = Rails.root.join("script/release_test_matrix").freeze
  DOMAINS = %w[deployment bootstrap invitation principal suspension recovery transfer].freeze

  test "checker can be loaded without executing its CLI entrypoint" do
    assert_nothing_raised { load CHECKER.to_s }
    assert defined?(CoverageGate::ManifestCheck)
    assert Object.private_method_defined?(:run_coverage_check_cli)
  end

  test "coverage matrix explains the missing event comparison SHA before running suites" do
    _stdout, stderr, status = Open3.capture3(
      { "SCREENOTE_COVERAGE_BASE_SHA" => nil },
      MATRIX.to_s,
      "coverage"
    )

    assert_not status.success?
    assert_includes stderr, "SCREENOTE_COVERAGE_BASE_SHA is required for this gate"
  end

  test "coverage matrix preflights applicability before running either edition suite" do
    coverage_gate = MATRIX.read.match(/^  coverage\).*?^    ;;$/m).to_s

    assert_not_empty coverage_gate
    assert_includes MATRIX.read, "readonly COVERAGE_NOT_APPLICABLE_EXIT=3"
    assert_includes coverage_gate, "--preflight"
    assert_includes coverage_gate, '"${COVERAGE_NOT_APPLICABLE_EXIT}") exit 0'
    assert_not_includes coverage_gate, "Changed security coverage:"
    assert_operator coverage_gate.index("--preflight"), :<, coverage_gate.index("assert_mode_booted saas")
    assert_operator coverage_gate.index("--preflight"), :<,
      coverage_gate.index("read_self_hosted_manifest_group self_hosted self_hosted_tests")
  end

  test "coverage boot instruments only the matrix root process" do
    Dir.mktmpdir("screenote-coverage-boot") do |directory|
      script = <<~'RUBY'
        require "open3"
        require "rbconfig"

        output, status = Open3.capture2e(
          RbConfig.ruby,
          "-e",
          'state = defined?(SimpleCov) && SimpleCov.running ? "on" : "off"; puts "child-coverage=#{state}"'
        )
        puts output
        exit 1 unless status.success?
      RUBY
      env = {
        "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s,
        "COVERAGE" => "true",
        "RUBYOPT" => "-r#{COVERAGE_BOOT}",
        "SCREENOTE_COVERAGE_ROOT_PID" => nil,
        "SCREENOTE_DEFER_COVERAGE_GATE" => "1"
      }

      stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, "-e", script, chdir: directory)

      assert status.success?, [ stdout, stderr ].join("\n")
      assert_includes stdout, "child-coverage=off"
      assert_empty stderr
    end
  end

  test "manifest mode merges suites and requires complete changed line and branch coverage" do
    with_repository do |root, base, paths|
      source = <<~RUBY
        def security_decision(enabled)
          if enabled
            :allowed
          else
            :denied
          end
        end
      RUBY
      File.write(root.join(paths.fetch("deployment")), source)

      lines_a = [ 1, 1, 1, 1, 0, 1, 1 ]
      lines_b = [ 0, 0, 0, 0, 1, 0, 0 ]
      branches_a = branch_coverage(then_count: 1, else_count: 0)
      branches_b = branch_coverage(then_count: 0, else_count: 1)
      resultset = write_resultset(
        root,
        paths.fetch("deployment"),
        suites: [
          { "lines" => lines_a, "branches" => branches_a },
          { "lines" => lines_b, "branches" => branches_b }
        ]
      )
      manifest = write_manifest(root, paths)

      stdout, stderr, status = run_checker(
        root,
        resultset,
        "--manifest", manifest.to_s,
        "--base", base,
        env: { "MIN_COVERAGE" => "0" }
      )

      assert status.success?, stderr
      assert_equal <<~OUTPUT, stdout
        Changed security line coverage: 100.00% (7/7)
        Changed security branch coverage: 100.00% (2/2)
      OUTPUT
      assert_empty stderr
    end
  end

  test "manifest mode checks a pushed commit against its before SHA" do
    with_repository do |root, before_sha, paths|
      path = paths.fetch("deployment")
      File.write(root.join(path), "def pushed_security_path = :covered\n")
      git!(root, "add", "--", path)
      git!(root, "commit", "--quiet", "-m", "change security path")
      resultset = write_resultset(
        root,
        path,
        suites: [ { "lines" => [ 1 ], "branches" => {} } ]
      )

      stdout, stderr, status = run_checker(
        root,
        resultset,
        "--manifest", write_manifest(root, paths).to_s,
        "--base", before_sha
      )

      assert status.success?, stderr
      assert_includes stdout, "Changed security line coverage: 100.00% (1/1)"
      assert_empty stderr
    end
  end

  test "manifest mode passes explicitly as not applicable for a non-security HEAD diff" do
    with_repository do |root, base, paths|
      File.write(root.join("README.md"), "non-security change\n")
      git!(root, "add", "--", "README.md")
      git!(root, "commit", "--quiet", "-m", "change non-security source")

      stdout, stderr, status = run_checker(
        root,
        root.join("missing-resultset.json"),
        "--manifest", write_manifest(root, paths).to_s,
        "--base", base
      )

      assert status.success?, stderr
      assert_equal \
        "Changed security coverage: not applicable (no release-security manifest paths changed)\n",
        stdout
      assert_empty stderr
    end
  end

  test "manifest preflight distinguishes security changes without loading coverage results" do
    with_repository do |root, base, paths|
      manifest = write_manifest(root, paths)

      stdout, stderr, status = run_preflight(root, manifest, base)

      assert_equal 1, status.exitstatus
      assert_empty stdout
      assert_includes stderr, "coverage comparison diff is empty"

      File.write(root.join("README.md"), "baseline\n")
      git!(root, "add", "--", "README.md")
      git!(root, "commit", "--quiet", "-m", "add non-security source")
      base = git!(root, "rev-parse", "HEAD").strip
      File.write(root.join("README.md"), "uncommitted non-security change\n")

      stdout, stderr, status = run_preflight(root, manifest, base)

      assert_equal 3, status.exitstatus, stderr
      assert_equal \
        "Changed security coverage: not applicable (no release-security manifest paths changed)\n",
        stdout
      assert_empty stderr

      File.write(root.join(paths.fetch("deployment")), "def changed_security_path = :covered\n")
      stdout, stderr, status = run_preflight(root, manifest, base)

      assert status.success?, stderr
      assert_equal "Changed security coverage: applicable\n", stdout
      assert_empty stderr
    end
  end

  test "manifest preflight rejects removal of a guarded path from current membership" do
    with_repository do |root, _base, paths|
      removed = "app/deployment_guard.rb"
      File.write(root.join(removed), "def deployment_guard = :baseline\n")
      manifest = write_manifest(root, paths, additional_paths: { "deployment" => [ removed ] })
      git!(root, "add", "--", removed, manifest.basename.to_s)
      git!(root, "commit", "--quiet", "-m", "add guarded source")
      base = git!(root, "rev-parse", "HEAD").strip

      File.write(root.join(removed), "def deployment_guard = :changed\n")
      narrowed = valid_manifest(paths)
      narrowed["discovery"] = paths.values.sort
      File.write(manifest, YAML.dump(narrowed))

      stdout, stderr, status = run_preflight(root, manifest, base)

      assert_equal 1, status.exitstatus
      assert_empty stdout
      assert_includes stderr, "coverage manifest removed guarded paths: #{removed}"
    end
  end

  test "manifest mode rejects an uncovered changed line even when MIN_COVERAGE lowers the legacy threshold" do
    with_repository do |root, base, paths|
      source = "def changed_security_path\n  :covered\nend\n"
      File.write(root.join(paths.fetch("deployment")), source)
      resultset = write_resultset(
        root,
        paths.fetch("deployment"),
        suites: [ { "lines" => [ 1, 0, 1 ], "branches" => {} } ]
      )

      _stdout, stderr, status = run_checker(
        root,
        resultset,
        "--manifest", write_manifest(root, paths).to_s,
        "--base", base,
        env: { "MIN_COVERAGE" => "0" }
      )

      assert_not status.success?
      assert_includes stderr, "uncovered changed lines"
      assert_includes stderr, "#{paths.fetch('deployment')}:2"
    end
  end

  test "manifest mode rejects an uncovered branch arm on a changed line" do
    with_repository do |root, base, paths|
      source = <<~RUBY
        def security_decision(enabled)
          if enabled
            :allowed
          else
            :denied
          end
        end
      RUBY
      File.write(root.join(paths.fetch("deployment")), source)
      resultset = write_resultset(
        root,
        paths.fetch("deployment"),
        suites: [
          {
            "lines" => Array.new(source.lines.length, 1),
            "branches" => branch_coverage(then_count: 1, else_count: 0)
          }
        ]
      )

      _stdout, stderr, status = run_checker(
        root,
        resultset,
        "--manifest", write_manifest(root, paths).to_s,
        "--base", base
      )

      assert_not status.success?
      assert_includes stderr, "uncovered changed branch arms"
      assert_includes stderr, "#{paths.fetch('deployment')}:5"
    end
  end

  test "manifest mode selects branches when a predicate continuation line changes" do
    with_repository do |root, _base, paths|
      before = <<~RUBY
        def security_decision(primary, secondary)
          if primary &&
              secondary
            :allowed
          else
            :denied
          end
        end
      RUBY
      after = before.sub("      secondary", "      !secondary")
      File.write(root.join(paths.fetch("deployment")), before)
      git!(root, "add", "--", paths.fetch("deployment"))
      git!(root, "commit", "--quiet", "-m", "multiline predicate baseline")
      base = git!(root, "rev-parse", "HEAD").strip
      File.write(root.join(paths.fetch("deployment")), after)
      resultset = write_resultset(
        root,
        paths.fetch("deployment"),
        suites: [
          {
            "lines" => Array.new(after.lines.length, 1),
            "branches" => {
              "[:if, 0, 2, 2, 7, 5]" => {
                "[:then, 1, 4, 4, 4, 12]" => 1,
                "[:else, 2, 6, 4, 6, 11]" => 0
              }
            }
          }
        ]
      )

      stdout, stderr, status = run_checker(
        root,
        resultset,
        "--manifest", write_manifest(root, paths).to_s,
        "--base", base
      )

      assert_not status.success?
      assert_includes stdout, "Changed security branch coverage: 50.00% (1/2)"
      assert_includes stderr, "uncovered changed branch arms"
      assert_includes stderr, "#{paths.fetch('deployment')}:6"
    end
  end

  test "manifest mode rejects a changed file absent from branch enabled results" do
    with_repository do |root, base, paths|
      File.write(root.join(paths.fetch("deployment")), "def changed_security_path = :covered\n")
      resultset = root.join("resultset.json")
      File.write(
        resultset,
        JSON.generate(
          "rails-test" => {
            "coverage" => {
              root.join(paths.fetch("deployment")).to_s => { "lines" => [ 1 ] }
            },
            "timestamp" => Time.now.to_i
          }
        )
      )

      _stdout, stderr, status = run_checker(
        root,
        resultset,
        "--manifest", write_manifest(root, paths).to_s,
        "--base", base
      )

      assert_not status.success?
      assert_includes stderr, "changed manifest file is absent from branch-enabled coverage"
      assert_includes stderr, paths.fetch("deployment")
    end
  end

  test "manifest mode rejects a stale coverage line map" do
    with_repository do |root, base, paths|
      File.write(root.join(paths.fetch("deployment")), "def changed_security_path\n  :covered\nend\n")
      resultset = write_resultset(
        root,
        paths.fetch("deployment"),
        suites: [ { "lines" => [ 1 ], "branches" => {} } ]
      )

      _stdout, stderr, status = run_checker(
        root,
        resultset,
        "--manifest", write_manifest(root, paths).to_s,
        "--base", base
      )

      assert_not status.success?
      assert_includes stderr, "stale coverage line map"
      assert_includes stderr, paths.fetch("deployment")
    end
  end

  test "manifest schema rejects unknown domains unsorted paths duplicates and wrong extensions" do
    with_repository do |root, base, paths|
      File.write(root.join(paths.fetch("deployment")), "def changed_security_path = :covered\n")
      resultset = write_resultset(
        root,
        paths.fetch("deployment"),
        suites: [ { "lines" => [ 1 ], "branches" => {} } ]
      )
      cases = {
        "discovery" => lambda do |manifest|
          manifest.delete("discovery")
        end,
        "unknown domain" => lambda do |manifest|
          manifest.fetch("domains")["future"] = manifest.fetch("domains").delete("transfer")
        end,
        "sorted" => lambda do |manifest|
          second = "app/deployment_z.rb"
          File.write(root.join(second), "module DeploymentZ; end\n")
          manifest.fetch("domains").fetch("deployment").replace([ second, paths.fetch("deployment") ])
        end,
        "duplicate" => lambda do |manifest|
          manifest.fetch("domains").fetch("bootstrap").replace([ paths.fetch("deployment") ])
        end,
        ".rb" => lambda do |manifest|
          wrong = "app/not-ruby.txt"
          File.write(root.join(wrong), "not ruby\n")
          manifest.fetch("domains").fetch("deployment").replace([ wrong ])
        end
      }

      cases.each do |expected_error, mutation|
        manifest_data = valid_manifest(paths)
        mutation.call(manifest_data)
        manifest = root.join("manifest-#{expected_error.tr(' .', '--')}.yml")
        File.write(manifest, YAML.dump(manifest_data))

        _stdout, stderr, status = run_checker(
          root,
          resultset,
          "--manifest", manifest.to_s,
          "--base", base
        )

        assert_not status.success?, expected_error
        assert_includes stderr, expected_error
      end
    end
  end

  test "manifest schema rejects security files discovered outside the declared domains" do
    with_repository do |root, base, paths|
      omitted = "app/deployment_policy.rb"
      File.write(root.join(omitted), "def omitted_security_path = :uncovered\n")
      resultset = write_resultset(
        root,
        paths.fetch("deployment"),
        suites: [ { "lines" => [ 1 ], "branches" => {} } ]
      )
      manifest = valid_manifest(paths).merge("discovery" => [ "app/*.rb" ])
      manifest_path = root.join("security-coverage.yml")
      File.write(manifest_path, YAML.dump(manifest))

      _stdout, stderr, status = run_checker(
        root,
        resultset,
        "--manifest", manifest_path.to_s,
        "--base", base
      )

      assert_not status.success?
      assert_includes stderr, "coverage manifest discovery drift"
      assert_includes stderr, omitted
    end
  end

  test "manifest mode rejects an unknown or non ancestor base commit" do
    with_repository do |root, base, paths|
      File.write(root.join(paths.fetch("deployment")), "def changed_security_path = :covered\n")
      resultset = write_resultset(
        root,
        paths.fetch("deployment"),
        suites: [ { "lines" => [ 1 ], "branches" => {} } ]
      )
      manifest = write_manifest(root, paths)
      tree = git!(root, "rev-parse", "#{base}^{tree}").strip
      unrelated = git!(root, "commit-tree", tree, stdin_data: "unrelated root\n").strip

      {
        "unknown" => "f" * 40,
        "not an ancestor" => unrelated
      }.each do |expected_error, candidate|
        _stdout, stderr, status = run_checker(
          root,
          resultset,
          "--manifest", manifest.to_s,
          "--base", candidate
        )

        assert_not status.success?, expected_error
        assert_includes stderr, expected_error
      end
    end
  end

  test "manifest mode includes an untracked source file" do
    with_repository do |root, base, paths|
      untracked = "app/untracked_security.rb"
      source = "def untracked_security_path = :covered\n"
      File.write(root.join(untracked), source)
      resultset = write_resultset(
        root,
        untracked,
        suites: [ { "lines" => [ 1 ], "branches" => {} } ]
      )

      stdout, stderr, status = run_checker(
        root,
        resultset,
        "--manifest", write_manifest(root, paths, additional_paths: { "deployment" => [ untracked ] }).to_s,
        "--base", base
      )

      assert status.success?, stderr
      assert_includes stdout, "100.00% (1/1)"
      assert_empty stderr
      assert_equal "?? #{untracked}", git!(root, "status", "--short", "--", untracked).strip
    end
  end

  test "manifest mode includes an ignored untracked source file" do
    with_repository do |root, base, paths|
      ignored = "app/ignored_security.rb"
      File.write(root.join(".gitignore"), "#{ignored}\n")
      File.write(root.join(ignored), "def ignored_security_path = :uncovered\n")
      resultset = write_resultset(
        root,
        ignored,
        suites: [ { "lines" => [ 0 ], "branches" => {} } ]
      )

      _stdout, stderr, status = run_checker(
        root,
        resultset,
        "--manifest", write_manifest(root, paths, additional_paths: { "deployment" => [ ignored ] }).to_s,
        "--base", base
      )

      assert_not status.success?
      assert_includes stderr, "uncovered changed lines"
      assert_includes stderr, "#{ignored}:1"
      assert_empty git!(root, "status", "--short", "--", ignored)
    end
  end

  test "manifest mode rejects paths escaping the repository" do
    with_repository do |root, base, paths|
      outside = root.parent.join("outside-security.rb")
      File.write(outside, "def outside = :unsafe\n")
      paths["deployment"] = "../#{outside.basename}"
      manifest = write_manifest(root, paths)
      resultset = root.join("resultset.json")
      File.write(resultset, JSON.generate("rails-test" => { "coverage" => {}, "timestamp" => Time.now.to_i }))

      _stdout, stderr, status = run_checker(
        root,
        resultset,
        "--manifest", manifest.to_s,
        "--base", base
      )

      assert_not status.success?
      assert_includes stderr, "escapes the repository"
    ensure
      FileUtils.rm_f(outside) if outside
    end
  end

  test "manifest mode rejects an empty diff and malformed SimpleCov branch identifiers" do
    with_repository do |root, base, paths|
      unchanged_resultset = write_resultset(
        root,
        paths.fetch("deployment"),
        suites: [ { "lines" => [ 1 ], "branches" => {} } ]
      )
      manifest = write_manifest(root, paths)

      _stdout, stderr, status = run_checker(
        root,
        unchanged_resultset,
        "--manifest", manifest.to_s,
        "--base", base
      )
      assert_not status.success?
      assert_includes stderr, "coverage comparison diff is empty"

      File.write(root.join(paths.fetch("deployment")), "def changed_security_path = :covered\n")
      malformed = write_resultset(
        root,
        paths.fetch("deployment"),
        suites: [
          {
            "lines" => [ 1 ],
            "branches" => { "not-a-simplecov-id" => { "also-invalid" => 1 } }
          }
        ]
      )
      _stdout, stderr, status = run_checker(
        root,
        malformed,
        "--manifest", manifest.to_s,
        "--base", base
      )
      assert_not status.success?
      assert_includes stderr, "malformed SimpleCov branch identifier"
    end
  end

  test "legacy mode keeps its positional interface and uses SimpleCov nil zero merge semantics" do
    Dir.mktmpdir("screenote-legacy-coverage") do |directory|
      root = Pathname(directory)
      resultset = root.join("resultset.json")
      File.write(
        resultset,
        JSON.generate(
          "suite-a" => {
            "coverage" => {
              "/tmp/example.rb" => {
                "lines" => [ 1, nil, 0 ],
                "branches" => { "condition" => { "arm" => 0 } }
              }
            },
            "timestamp" => Time.now.to_i
          },
          "suite-b" => {
            "coverage" => {
              "/tmp/example.rb" => {
                "lines" => [ 0, 0, 1 ],
                "branches" => { "condition" => { "arm" => 1 } }
              }
            },
            "timestamp" => Time.now.to_i
          }
        )
      )

      stdout, stderr, status = Open3.capture3(
        { "MIN_COVERAGE" => "100" },
        RbConfig.ruby,
        CHECKER.to_s,
        resultset.to_s,
        chdir: root.to_s
      )

      assert status.success?, stderr
      assert_equal "Line coverage: 100.00%\nBranch coverage: 100.00%\n", stdout
      assert_empty stderr
    end
  end

  private

  def with_repository
    Dir.mktmpdir("screenote-coverage-gate") do |directory|
      root = Pathname(directory)
      git!(root, "init", "--quiet", "--initial-branch=main")
      git!(root, "config", "user.email", "coverage@example.test")
      git!(root, "config", "user.name", "Coverage Contract")
      paths = DOMAINS.to_h { |domain| [ domain, "app/#{domain}.rb" ] }
      paths.each do |domain, path|
        FileUtils.mkdir_p(root.join(path).dirname)
        File.write(root.join(path), "module #{domain.camelize}; end\n")
      end
      manifest = write_manifest(root, paths)
      git!(root, "add", "--", *paths.values, manifest.basename.to_s)
      git!(root, "commit", "--quiet", "-m", "baseline")
      base = git!(root, "rev-parse", "HEAD").strip

      yield root, base, paths
    end
  end

  def valid_manifest(paths)
    {
      "version" => 1,
      "domains" => DOMAINS.to_h { |domain| [ domain, [ paths.fetch(domain) ] ] },
      "discovery" => [ "app/*.rb" ]
    }
  end

  def write_manifest(root, paths, additional_paths: {})
    root.join("security-coverage.yml").tap do |path|
      manifest = valid_manifest(paths)
      additional_paths.each do |domain, additions|
        manifest.fetch("domains").fetch(domain).concat(additions).sort!
      end
      File.write(path, YAML.dump(manifest))
    end
  end

  def write_resultset(root, relative_path, suites:)
    absolute_path = root.join(relative_path).to_s
    resultset = suites.each_with_index.to_h do |coverage, index|
      [
        "suite-#{index + 1}",
        {
          "coverage" => { absolute_path => coverage },
          "timestamp" => Time.now.to_i
        }
      ]
    end
    root.join("resultset.json").tap { |path| File.write(path, JSON.generate(resultset)) }
  end

  def branch_coverage(then_count:, else_count:)
    {
      "[:if, 0, 2, 2, 6, 5]" => {
        "[:then, 1, 3, 4, 3, 12]" => then_count,
        "[:else, 2, 5, 4, 5, 11]" => else_count
      }
    }
  end

  def run_checker(root, resultset = nil, *arguments, env: {})
    command = [ RbConfig.ruby, CHECKER.to_s ]
    command << resultset.to_s if resultset
    Open3.capture3(
      env,
      *command,
      *arguments,
      chdir: root.to_s
    )
  end

  def run_preflight(root, manifest, base)
    run_checker(
      root,
      nil,
      "--manifest", manifest.to_s,
      "--base", base,
      "--preflight"
    )
  end

  def git!(root, *arguments, stdin_data: "")
    stdout, stderr, status = Open3.capture3(
      "git",
      *arguments,
      stdin_data: stdin_data,
      chdir: root.to_s
    )
    raise "git #{arguments.join(' ')} failed: #{stderr}" unless status.success?

    stdout
  end
end
