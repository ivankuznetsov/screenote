# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Whitespace", "git diff --check"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  if ENV["REQUIRE_COVERAGE"] == "true"
    step "Tests: Rails coverage", "env COVERAGE=true bin/rails test && bin/check_coverage"
  else
    step "Tests: Rails", "bin/rails test"
  end

  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  if File.exist?("go.mod")
    step "Tests: Go", "env GOFLAGS=-mod=mod go test ./..."
  end

  # Optional: Run system tests
  # step "Tests: System", "bin/rails test:system"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
