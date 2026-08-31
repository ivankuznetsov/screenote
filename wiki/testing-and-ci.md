---
title: Testing and CI
type: operations
source: test/, bin/ci, config/ci.rb, .github/workflows/ci.yml, .github/workflows/release-qualification.yml
created: 2026-07-28
updated: 2026-08-31
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

Stale parallel test databases cause misleading `SQLite3::BusyException`
failures spread across unrelated tests. If a run reports many lock errors in
fixture loading, remove `storage/test.sqlite3*` and re-run
`bin/rails db:test:prepare` before investigating the code.

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

`test/system/image_attachments_test.rb` is the browser contract for image
attachments. Every input path is proved all the way to a posted message rather
than only to an attachment: root, reply, and unresolve each post several images
collected through the picker, composer-scoped drop, and a real clipboard paste.
It also covers mixed clipboard input, per-file progress, alt text, removal, a
failed upload holding the submit control closed until a retry finishes it, 422
rehydration, the gallery placeholder warming into responsive thumbnails, the
modal viewer for one image and for several — navigation hidden when there is
nothing to navigate to, zoom, download, open-original, focus handling — narrow
layout, the explicit light and dark component contexts for both the composer
and the nested viewer, and the composer's polite live region. Two geometry contracts sit side by side: against the full-size
`desktop_screenshot.png` fixture the clamped overlay must leave the selected
region completely uncovered, and against a thumbnail-sized capture it must at
least stay one compact rail inside the image.

`SCREENOTE_EVIDENCE_DIR` turns any browser run into a recorded one. Each test
writes a Playwright trace (`<test>.trace.zip`), and `capture_evidence` writes a
named frame plus the page facts a picture cannot show — resolved media paths,
srcset candidates, component context, measured geometry.
`script/attachment_browser_evidence` runs the attachment suite that way,
extracts each trace into an ordered filmstrip, and encodes that filmstrip into
a watchable `<test>.webm`.

Both halves fail closed. A trace that cannot be started or cannot be written
fails its test rather than printing a note, and the script refuses a non-empty
output directory and requires one trace per declared test in the suite, so a
stale directory or a run that stopped early cannot satisfy the gate.

The video is encoded from the trace screencast, not recorded by the browser.
Playwright's own `record_video_dir` cannot be used here: `reset!` in
`capybara-playwright-driver` asks the page for its video path while the page is
still open, and `Playwright::Video#path` blocks on a future that the page-close
event rejects, so a run that sets the option hangs and leaves a zero-byte file.
The trace screencast carries the same picture — roughly 20 frames a second for
the whole length of a test — and each frame keeps the millisecond it was
captured at in its name, so the concat encode reproduces the run's real timing
rather than a nominal frame rate. Frames must be ordered by that numeric tail
read from the bare file name; the enclosing path contains hyphens of its own.
Anything read from the live browser must happen in `before_teardown`, because
Capybara closes the context in `after_teardown`, ahead of ordinary teardown
callbacks.

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
security scans, Rails tests, seed validation, and the Go tests as
`env GOFLAGS=-mod=mod go test ./...` — the module flag is required because the
repository's top-level `vendor/` directory belongs to Ruby, and a bare
`go test` reads it as an inconsistent Go vendor tree and refuses to run. Set
`REQUIRE_COVERAGE=true` to enforce the SimpleCov line and branch thresholds;
coverage mode forces one Rails worker for stable accounting. System tests are
currently commented out as optional in `config/ci.rb`, so run the Playwright
command above separately when browser behavior changes.

One adapter-specific workflow sits outside that boundary. `concurrency-qualification.yml`
runs `script/release_test_matrix attachment-lifecycle` against a PostgreSQL
server database so real row locks exercise lock ordering, atomic claim,
aggregate races, and the cleanup/remove/submit races that SQLite can only assert
by outcome. It is a required status check on the default branch, and
`bin/release-validate` asserts both that requirement and the workflow's own
shape, so the branch cannot merge with that evidence unproven. It is a separate workflow precisely so `ci.yml` stays free of
adapter-specific content and the portability contract keeps passing. The
ephemeral, runner-local PostgreSQL service uses trust authentication and a
credential-free loopback URL, so the workflow does not carry a reusable test
password in its published source.

Every race in that suite proves real overlap before it asserts an outcome: the
helper starts the second operation, confirms it is blocked on the transaction
the first one is parked inside, and only then releases. Serial execution cannot
pass. The aggregate race runs against the real 50 MB message ceiling — the
batch is seeded with recorded byte sizes up to exactly one more file's worth of
room — rather than a stubbed limit.

The gate names one list of suites and runs it against whatever database is
configured, so the SQLite and server-database halves cannot drift apart. Two
cases in that list only mean something on a server database — the account
byte-ceiling serialization race and the adapter assertion that keeps the
qualification honest — and they skip on SQLite.
`script/attachment_server_database_qualification` boots an ephemeral server
database, exports `SCREENOTE_SERVER_DATABASE_QUALIFICATION=1`, and reruns the
gate, so that half is reproducible outside CI rather than only inside it.
The same lifecycle list includes a barrier-driven concurrent image-comment
retry: PostgreSQL must return one `created` and one `replayed` result pointing
at the same comment, attachment, and blob, rather than merely producing the
right final row count by sequential execution.

The `s3` gate carries the delivery half of the same contract.
`test/integration/image_attachment_s3_delivery_contract_test.rb` points the
whole application at the configured object store and drives the protected
session and bearer routes through it, which is the only way to prove the
application streams the bytes itself: a Disk service has no presigned URL to
leak and no remote host to redirect to.
`script/attachment_object_store_qualification` supplies that store the same way
the database script supplies a database — an ephemeral MinIO container on the
same immutable image `container-s3` uses — and reruns the gate, so the delivery
half is reproducible outside CI too. It accepts an operator's own endpoint
through `SCREENOTE_S3_ENDPOINT` and its companions for a run against the hosted
provider. The gate exports `SCREENOTE_REQUIRE_S3=1`, which turns the suite's
"no store configured" skip into a failure, so a qualification run cannot pass
by not running.
The S3 suite also creates and replays an API image comment, streams those exact
provider bytes through the bearer media route, and injects a database failure
after staging to prove the unowned provider object is removed and no comment,
attachment, or blob row remains.

The required `public-cli` job pins an exact public CLI commit and runs
`script/release_test_matrix public-cli-source` against a real Rails test server.
That gate builds the checked-out CLI, proves unchanged body-only comments,
path and stdin image authoring, a same-key retry after a proxy reports failure
after the backend commits, and root plus reply attachment materialization with
exact bytes, private modes, and no token URLs. It also proves revoked and
expired credentials fail privately, and that an old server receives exactly
one unsupported image-route request with no text-only fallback. It owns a
scratch test database lifecycle and cleans its created comments, attachments,
and blobs so later tests do not inherit state. The `container-s3` job reruns
that same exact-CLI gate against MinIO, checks the selected Active Storage
service, and verifies the provider-backed bytes. The real test server keeps the
self-hosted storage configuration but does not start the production-only Solid
Queue Puma supervisor. This is source compatibility evidence; the tagged
HTTP/HTTPS and release-image CLI qualification remains a separate release-only
gate.

The source workflow has one adapter-neutral `test` job for the Rails suite and
the self-hosted-only smoke tests. It replaces separate SQLite and PostgreSQL
application-test jobs and exercises the configured test database through
Active Record. PostgreSQL remains a choice in the hosted Kamal deployment, not
an application-test or release-qualification requirement. The integration
portability contract scans `app/`, `db/migrate/`, and `config/database.yml` so
PostgreSQL-specific application behavior cannot silently re-enter that
boundary.

The required-PR source-release coverage gate is narrower and stricter than the
legacy whole-application option. `script/release_test_matrix coverage` first
compares the working tree with the exact event comparison commit: the pull
request's base SHA for pull-request runs and `github.event.before` for pushes
to `main`. The workflow passes that full SHA explicitly and the matrix rejects
missing, malformed, unavailable, non-ancestor, or genuinely empty overall
comparisons. It also validates the positive manifest, its discovery union, and
the guarded-path membership at both the base and current revision before
deciding applicability. Removing a previously guarded path fails closed. A
non-empty comparison with no guarded source changes reports an explicit
not-applicable success without running the two full suites. When a guarded path
changed, the matrix starts SimpleCov through `RUBYOPT` before Rails can load
edition-specific code and merges the independent SaaS and positive-manifest
self-hosted runs. For a local pre-PR run, use
`SCREENOTE_COVERAGE_BASE_SHA=<full-ancestor-sha> script/release_test_matrix coverage`.
The explicit
`test/manifests/release_security_coverage.yml` source manifest must name the
deployment, bootstrap, invitation, principal, suspension, recovery, and
administrator-transfer boundaries. Every executable changed line and changed
branch arm in those files must be covered; missing instrumentation, removed
guarded membership, source manifest drift, an invalid base, or an empty overall
comparison fails closed.
Coverage processes set `DISABLE_BOOTSNAP_COMPILE_CACHE=1`: Ruby cannot compile
Bootsnap instruction-sequence cache entries after branch/line coverage has
started, and a warm CI bundle cache must not make the coverage gate fail before
the suite runs.
The manifest includes every changed controller that delivers one of those
flows, and `CI / coverage` runs this gate for every pull request; controller
delivery code cannot be deferred to a release-only handoff check.
When applicable, the coverage job has a 45-minute budget because it runs the
complete SaaS and self-hosted suites sequentially before merging their results.
A 25-minute budget can cancel a healthy self-hosted run after the SaaS suite has
already passed, leaving the stricter dual-edition assertion unevaluated.
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
instead of trusting a committed status claim. Exact-image SaaS qualification
has not been removed: AMD64 and ARM64 each boot the retained candidate through
its production entrypoint with separate primary, cache, queue, and cable URLs.
The check verifies those roles and the SaaS installation identity through
Active Record without asserting an adapter name or server version. See
[[self-hosting]].
