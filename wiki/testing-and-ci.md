---
title: Testing and CI
type: operations
source: test/, bin/ci, config/ci.rb, .github/workflows/ci.yml
created: 2026-07-28
updated: 2026-08-06
tags: [testing, ci, minitest, capybara, playwright]
---

# Testing and CI

TLDR: Rails tests use Minitest, controller/model/job tests run through
`bin/rails test`, and browser regressions use Capybara with Playwright.
`bin/ci` is the complete non-browser local gate. The system suite is an
explicit separate command.

## Focused Rails tests

Use the repository bundle and serialize when exact SQL counts or shared image
fixtures matter:

```sh
BUNDLE_PATH=vendor/bundle PARALLEL_WORKERS=1 bundle exec bin/rails test \
  test/controllers/projects_controller_test.rb
```

Image-processing tests require libvips. The helper `require_vips!` skips those
tests explicitly when the system dependency is absent instead of hiding a
processing failure.

Every CI job that boots Rails must install libvips before `ruby/setup-ruby`
hands control to the test command. The application loads the Vips initializer
at boot even when a focused contract does not transform an image; a focused
backup/restore job without the runtime library fails before its tests begin.
The public-CLI digest and release-artifact jobs follow the same rule. Commands
that inspect a bundled Ruby dependency, such as Playwright version discovery,
run through `bundle exec ruby` so a cache-restored bundle is visible.

## Browser tests

System tests run the application through Capybara's in-process server and use
the Playwright driver:

```sh
BUNDLE_PATH=vendor/bundle CAPYBARA_RUN_SERVER=true PARALLEL_WORKERS=1 \
  bundle exec bin/rails test:system
```

Use the same environment for a focused system file. Serial execution keeps the
shared server, jobs, and Active Storage fixtures deterministic.

`script/release_test_matrix system-collaboration` clobbers ignored precompiled
assets before starting the in-process server. Propshaft gives
`public/assets/.manifest.json` precedence over source assets, so artifacts left
by an earlier image or precompile probe could otherwise make Playwright execute
stale JavaScript while the test reports against current source.

`ApplicationSystemTestCase` replaces the test environment's `NullStore` with a
fresh in-memory cache for each test and restores it during teardown. This keeps
rate-limit state isolated while allowing fail-closed request paths to run
through the in-process server; production continues to use Solid Cache and
still returns 503 when its limiter backend is unavailable.

`test/system/annotations_test.rb` is the browser contract for the review
workspace. It covers point clicks, area drags, in-place composer placement,
fullscreen with comments open or collapsed, marker/thread selection, long
captures, and a multi-user thread where one project member creates feedback and
another replies before the first member reads the response.

The required self-hosted browser manifest repeats that cross-session outcome in
the edition it ships: the original collaborator reloads and reads the other
member's reply. Its instance-administration scenarios also prove that suspension
invalidates an existing browser session, restoration requires a fresh sign-in,
and a private recovery link resets credentials once in a separate session while
rejecting replay and the former password.

`DEVICE_SCALE_FACTOR` configures the Playwright context for responsive-image
proof. Run `test/system/pages_test.rb` at both `1` and `2`; its responsive card
test verifies `currentSrc` selects the 480w and 960w candidates respectively
and confirms the selected representation appears in the browser resource log.

## Overview performance contracts

`ProjectsControllerTest` treats SQL shape as a regression contract:

- snapshot-filtered and unfiltered eight-page project views must use no more
  than 14 application SQL statements after caches are cleared;
- each image-bearing overview request must bulk-load tracked Active Storage
  variant records exactly once;
- adding many projects with thumbnail pages may add only a constant number of
  project-index queries;
- unwarmed cards must emit no named-variant representation URL, create no
  variant records, and enqueue no request-time work.

These tests cover request composition. Actual thumbnail transformation,
generation checks, and idempotency are covered by the screenshot thumbnail job,
model, and Rake task tests.

## Full gate

`bin/ci` installs missing dependencies and runs formatting/whitespace checks,
security scans, Rails tests, seed validation, and any configured Go tests. Set
`REQUIRE_COVERAGE=true` to enforce the SimpleCov line and branch thresholds;
coverage mode forces one Rails worker for stable accounting. System tests are
currently commented out as optional in `config/ci.rb`, so run the Playwright
command above separately when browser behavior changes.

The required-PR source-release coverage gate is narrower and stricter than the
legacy whole-application option. `script/release_test_matrix coverage` starts
SimpleCov through `RUBYOPT` before Rails can load edition-specific code, merges
the independent SaaS and positive-manifest self-hosted runs, and compares the
working tree with the exact event comparison commit: the pull request's base
SHA for pull-request runs and `github.event.before` for pushes to `main`. The
workflow passes that full SHA explicitly and the matrix rejects missing,
malformed, unavailable, or non-ancestor values before starting the suites. For
a local pre-PR run, use
`SCREENOTE_COVERAGE_BASE_SHA=<full-ancestor-sha> script/release_test_matrix coverage`.
The explicit
`test/manifests/release_security_coverage.yml` source manifest must name the
deployment, bootstrap, invitation, principal, suspension, recovery, and
administrator-transfer boundaries. Every executable changed line and changed
branch arm in those files must be covered; missing instrumentation, source
manifest drift, an invalid base, or an empty security diff fails closed.
Coverage processes set `DISABLE_BOOTSNAP_COMPILE_CACHE=1`: Ruby cannot compile
Bootsnap instruction-sequence cache entries after branch/line coverage has
started, and a warm CI bundle cache must not make the coverage gate fail before
the suite runs.
The manifest includes every changed controller that delivers one of those
flows, and `CI / coverage` runs this gate for every pull request; controller
delivery code cannot be deferred to a release-only handoff check.
The coverage job has a 45-minute budget because it runs the complete SaaS and
self-hosted suites sequentially before merging their results. A 25-minute
budget can cancel a healthy self-hosted run after the SaaS suite has already
passed, leaving the stricter dual-edition assertion unevaluated.
Integration and system test bases replace the test environment's `NullStore`
with a fresh controller `MemoryStore` for each test, then restore it in teardown.
This keeps the production fail-closed rate-limit wrappers active in tests
without sharing throttle state across cases.
Sorted discovery patterns must expand to exactly the union of the seven domain
lists, including ignored untracked paths, so a newly added security source
cannot silently sit outside the positive manifest. Branch selection intersects
changed lines with each SimpleCov condition and arm's full source range, which
also covers continuation lines in multiline predicates.

Critical admission and authority races use a deterministic one-shot barrier
inside the first transaction after it holds the intended installation, user,
invitation, or authentication-token lock. A second independent connection must
remain blocked before the first is released; outcome-only simultaneous-start
tests are not sufficient proof because they can accidentally execute serially.

Final-image dependency probes must execute Ruby through Bundler. The release
image intentionally isolates deployment gems under `BUNDLE_PATH`, so a bare
`ruby` process is not equivalent to the Rails runtime and can report false
missing-gem failures. The CI image probe uses `bundle exec ruby` and verifies
both the selected S3 SDK and libvips binding from the final image.

Non-interactive commands inside a running Compose service use the portable
short `exec -T` spelling. The hosted runner's Compose 2.38.2 frontend exposes
the case-sensitive long spelling `--no-TTY`, while other plugin versions accept
`--no-tty`; the short form works across both. A rejected poll must not disguise
a healthy container as a durability timeout. Source contracts cover the
final-image processing poll, backup restore verification, and operator
diagnostics command.

Executable-level backup, restore, and diagnostics tests preserve the production
host contract at exactly uid/gid 1000. Their isolated child Ruby process loads a
test-only identity namespace that maps those two constants to the child's real
identity so a hosted UID 1001 runner can own its private fixtures. The preload
aborts outside `RAILS_ENV=test`; production binaries expose no environment
override. A user-namespace regression runs the same contracts as UID 1001/GID
127 to keep the harness independent of developer-machine identity.

Required pull-request jobs prove source contracts and are recorded with
`scope: pr_contract_only`; their names or success conclusions are never release
qualification evidence. The separate manual release-qualification workflow
downloads the exact retained candidate artifact by live ID, verifies its bytes
and OCI identities, and emits one redacted artifact only after all eight
architecture, edition, recovery, load, and public-CLI outcomes pass. Publish
authorization downloads and compares those exact bytes through the Actions API
instead of trusting a committed status claim. See [[self-hosting]].
