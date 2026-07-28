# Wiki Changelog

Append-only log of all wiki operations.

<!-- BEGIN GENERATED WIKI LOG FRAGMENTS -->
## [2026-07-28T17:27:45Z] Overview thumbnail and viewport-write guards

**Action:** Refreshed overview-thumbnail delivery and annotation-write documentation after the review hardening commit made request rendering depend on preloaded tracked variants, made partial thumbnail processing retryable, and bound annotation viewport writes to the selected screenshot.
**Pages updated:** `wiki/models/screenshot-image.md`, `wiki/controllers/web-controllers.md`, `wiki/frontend-review-ui.md`, `wiki/gaps.md`, `wiki/index.md`
**Index:** Page count remains 39; the ScreenshotImage and review-UI entries now expose the new overview-thumbnail coverage.
**Behavior:** Overview GETs emit no Active Storage representation URL until all three named variants are present in the current blob's preloaded variant records. Unwarmed page cards show `Thumbnail processing`, project strips omit the image, and neither path processes variants or enqueues work. `ScreenshotThumbnailJob` uses a 10-second, three-attempt retry for processing failures and skips already tracked variant digests on a later attempt. Annotation create/update rejects any nonblank viewport missing from the selected screenshot, while blank input preserves the create default or persisted update value.
**Source:** commit `b1681b0e7babb6e26cc7e0bec8bed9935a1f5f35`; `app/controllers/annotations_controller.rb`, `app/jobs/screenshot_thumbnail_job.rb`, `app/models/screenshot_image.rb`, `app/views/projects/index.html.erb`, `app/views/projects/show.html.erb`, and their controller, job, model, and system tests read with `git show`.
**Uncertainty:** The configured main wiki path `/home/asterio/wikis/master/wiki` remains unavailable, so cross-project context could not be searched; the ongoing gap remains recorded in `wiki/gaps.md`.
**Notes:** Updated only files under `wiki/`. Did not run QMD or edit compiled `wiki/log.md`.

## [2026-07-28T17:00:00Z] Workspace routing and snapshot thumbnail selection

**Action:** Refreshed the page-workspace and snapshot documentation after project cards adopted the shared workspace-route helper, legacy screenshot redirects tied status validation to the Annotation enum, and snapshot thumbnail selection moved from Ruby-side de-duplication to a deterministic SQL selection.
**Pages updated:** `wiki/frontend-review-ui.md`, `wiki/controllers/web-controllers.md`, `wiki/models/snapshot.md`, `wiki/gaps.md`
**Pages verified unchanged:** `wiki/index.md`, `wiki/routes.md`, `wiki/data-model.md`, `wiki/dependencies.md`
**Behavior:** A project card with a selected screenshot routes to `/pages/:page_id?version_id=:screenshot_id`; cards without a selected version retain the bare page route. Legacy screenshot and viewport URLs redirect to that workspace, forwarding only screenshot-backed viewports and enum-backed annotation statuses.
**Selection:** `Snapshot#thumbnails_for` now uses a correlated anti-existence query to return only the newest ready screenshot for each requested page, with `id` as the tie-break when timestamps match, while preserving the viewport-image preload used by project cards.
**Source:** commit `206ee512a5cb7b671e45e7ac721e120cb1f73f27`; `app/controllers/concerns/page_workspace_navigation.rb`, `app/controllers/pages_controller.rb`, `app/controllers/screenshots_controller.rb`, `app/models/snapshot.rb`, `app/views/projects/show.html.erb`, `test/models/snapshot_test.rb`, and `test/system/api_upload_test.rb` read with `git show`.
**Uncertainty:** The configured main wiki path `/home/asterio/wikis/master/wiki` remains unavailable, so cross-project context could not be searched; the ongoing gap is recorded in `wiki/gaps.md`.
**Notes:** Updated only files under `wiki/`. Did not run QMD or edit compiled `wiki/log.md`.

## [2026-07-28T16:53:57Z] Page workspace navigation tests

**Action:** Refreshed page-workspace navigation and screenshot-review regression coverage after the page system tests were aligned with the established workspace contract.
**Pages updated:** `wiki/frontend-review-ui.md`
**Pages verified unchanged:** `wiki/index.md`, `wiki/gaps.md`
**Source:** `test/system/pages_test.rb` on `fix/page-workspace-navigation`, plus the committed page and screenshot workspace views and controllers used by those tests.
**Notes:** The queued diff is test-only. It replaces obsolete breadcrumb traversal with browser-history or project-navigation returns, targets the `Edit page` label, and verifies that a second upload starts directly from the selected-version workspace. It changes no runtime architecture, route, API, dependency, or data-model behavior. The configured main wiki path remains unavailable; that existing uncertainty is already recorded in `wiki/gaps.md`. Did not run QMD or edit compiled `wiki/log.md`.

## [2026-07-13T22:11:00Z] Screenshot review navigation and geometry

**Action:** Documented the project-card shortcut for a lone usable screenshot, sticky long-image annotation behavior, sidebar-local form scrolling with scroll-preserving comment focus, and Annotorious wrapper-based mobile centering and pin coordinates.
**Pages added:** wiki/frontend-review-ui.md
**Pages updated:** wiki/index.md, wiki/gaps.md, wiki/controllers/web-controllers.md
**Decision:** Responsive images remain variants of one logical screenshot. Review navigation skips the version grid only when exactly one usable logical screenshot exists, and all percentage annotation geometry is resolved against the visible image wrapper rather than the wider canvas.
**Source:** app/views/projects/show.html.erb, app/javascript/controllers/annotorious_controller.js, app/assets/stylesheets/application.css, regression tests in test/controllers/projects_controller_test.rb and test/system/annotations_test.rb

## [2026-07-13T21:49:53Z] CLI workflow REST parity

**Action:** Added OAuth REST project creation and idempotent project-scoped annotation resolution, including stable response/error contracts, owner membership and plan-quota enforcement, user/API-key resolution authorship, scoped project listing, scoped-token cleanup on project deletion, and regression coverage for read-only, API-key, stale-writer, structured-comment, project-scoped, missing-project, and cross-project authorization paths.
**Pages updated:** wiki/api-cli.md, wiki/commands.md, wiki/controllers/api-controllers.md, wiki/routes.md, wiki/gaps.md, wiki/models/project.md, wiki/models/annotation.md
**Decision:** Project creation is a user-level operation available only to user-scoped OAuth `mcp_write` tokens. Annotation resolution remains project-scoped, accepts API keys or OAuth `mcp_write`, and locks at the shared model boundary so stale REST, web, and legacy MCP writers do not duplicate the resolution audit comment. Project-scoped OAuth tokens list and authorize only their bound member project; deleting that project deletes its scoped grants/tokens rather than widening the credentials.
**Source:** `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/projects_controller.rb`, `app/controllers/api/v1/annotation_resolutions_controller.rb`, `app/models/project.rb`, `app/models/annotation.rb`, REST routes, controller integration tests, and model tests
**Integration proof:** A disposable local OAuth user drove the public CLI branch through project creation, project listing, screenshot upload, annotation listing, private `0600` crop export, comment creation, initial resolution, and an `already_resolved` replay against the real Rails server. The temporary user, OAuth application, token, project, and files were removed afterward.

## [2026-07-13T19:00:30Z] CLI/OAuth documentation audit

**Action:** Reconciled internal command, roadmap, and initiative pages with the shipped public CLI, OAuth-only onboarding, RFC 8628 device login, and manifest snapshot workflow. Corrected the old in-repository Go install path and removed future-facing recommendations to expand MCP.
**Pages updated:** wiki/commands.md, wiki/api-cli.md, wiki/roadmap.md, wiki/plans-and-initiatives.md
**Decision:** The public `ivankuznetsov/screenote-cli` repository is the supported agent and automation surface. MCP remains server-side compatibility until its separately scoped sunset; new CLI and integration work should not extend the MCP tool surface.
**Source:** merged server PR #41, public CLI PR #5, deployed `https://screenote.ai/` and `/help`, OAuth authorization-server metadata, and the public CLI README/Go module

## [2026-07-13T15:55:01Z] OAuth device authorization

**Action:** Added the RFC 8628 server grant, authenticated approval/denial UI, secure short-lived grant storage, additive discovery/registration metadata, and callback-free CLI help for SSH, tmux, and other headless sessions. Dynamic registration consumes the RFC top-level JSON shape without Rails wrapper noise and uses an OAuth-neutral fallback client name. Removed manual CLI token/API-key onboarding from public documentation; the CLI documents OAuth sign-in only.
**Pages updated:** wiki/api-cli.md, wiki/controllers/oauth-controllers.md, wiki/routes.md, wiki/data-model.md, wiki/schema-evolution.md
**Decision:** Device login prints a one-time code and authorization link for explicit approval on another device; a complete link never approves by itself. Raw device codes are SHA-256-only at rest, human codes have 50 bits of entropy and fail-closed throttled verification, grants use an indexed 10-minute absolute expiry plus scheduled cleanup after 15 minutes of terminal-error retention, and token polls start at five seconds. Existing browser-based PKCE remains the default.
**Source:** `app/controllers/oauth/device_*`, `lib/screenote_oauth/device_code_grant.rb`, `app/models/oauth_device_grant.rb`, `db/migrate/20260713160000_create_oauth_device_grants.rb`, OAuth integration/controller tests, and public help/README changes

## [2026-07-13T13:31:35Z] CLI-first website onboarding

**Action:** Replaced public MCP-first onboarding with verified standalone CLI installation and usage guidance across the landing page, dashboard banner, help, account surfaces, OAuth consent, legal pages, and welcome email. The help page also documents the current dashboard-only project creation and web-only annotation resolution boundaries instead of overstating CLI parity.
**Pages updated:** wiki/active-areas.md, wiki/api-cli.md, wiki/controllers/web-controllers.md, wiki/gaps.md
**Decision:** The standalone CLI is the canonical public agent interface. The existing MCP runtime and OAuth scope identifiers remain unchanged because transport retirement is a separate effort.
**Source:** `app/views/static_pages`, `app/views/projects/index.html.erb`, account and OAuth views, welcome mailer views, and the public `screenote-cli` install/command contract

---
title: API key production schema repair
type: log
date: 2026-07-12
---

# API key production schema repair

**Action:** Documented and repaired historical API-key schema drift discovered by the production CLI OAuth smoke. A new irreversible forward migration converts any legacy plaintext tokens to SHA-256 digests and prefixes, preserves already-secure fresh databases, fails closed on unknown schemas, and bounds PostgreSQL lock acquisition. Added isolated SQLite coverage plus a dedicated PostgreSQL 16 CI lane for the production-specific migration path.

**Pages updated:** `wiki/models/api-key.md`, `wiki/schema-evolution.md`, and this log fragment.

**Source:** Production schema metadata, PR #3 and PR #4 history, `.github/workflows/ci.yml`, `db/migrate/20260212071431_create_api_keys.rb`, deleted migration `20260212151018_add_token_digest_to_api_keys.rb`, `app/models/api_key.rb`, and `app/services/api/bearer_authenticator.rb`.

---
title: Snapshot processing recovery and public CLI contract gate
type: log
date: 2026-07-12
---

# Snapshot processing recovery and public CLI contract gate

**Recovery:** An unchanged manifest replay now schedules dimension processing for every attached pending ScreenshotImage. This repairs the cross-database failure window where the application attachment commits but Solid Queue enqueue fails. Concurrency is keyed by ScreenshotImage and attachment blob generation, so same-blob retries deduplicate without dropping replacement analysis; stale jobs recheck the generation before writing dimensions.

**Contract:** The public CLI owns `testdata/contracts/snapshot-digests-v1.json`. Rails loads that exact file from a separately checked-out CLI repository, executes its primitive manifest/group vectors, and submits its normalized semantic manifest through `Snapshots::PrepareUpload`; no digest literals are copied into private tests.

**CI:** Pull requests pin an immutable public CLI commit as the supported v1 candidate. A separate scheduled/manual workflow checks public CLI `main` without making a moving branch a service merge gate.

**Coverage:** A forced queue-adapter failure proves the attachment remains pending and a byte-identical manifest replay enqueues recovery. Ready and unattached images remain no-op replays.

**Source:** `app/services/snapshots/ensure_processing.rb`, `app/services/snapshots/prepare_upload.rb`, `app/jobs/screenshot_dimension_job.rb`, service/contract tests, and GitHub Actions workflows.

---
title: Authenticated snapshot image upload
type: log
date: 2026-07-10
---

# Authenticated snapshot image upload

**Action:** Added the project-scoped API v1 raw-body upload resource for prepared ScreenshotImages.

**Security:** Bodies stream through a bounded, auto-unlinked temporary file. Actual MIME is detected from bytes and must be PNG/JPEG matching both the request header and prepared type; computed SHA-256 must match the prepared identity. Error responses contain only stable codes and context, never bytes, bearer credentials, or client-local paths.

**Idempotency:** Row locking permits exactly one attachment. Identical retries return success without another blob or job; failed processing retries reuse the attachment, return to pending, and enqueue one new dimension job. Concurrent coverage proves one attachment and one initial processing job.

**Compatibility:** OAuth `mcp_write` and project API keys are supported. The existing signed-token MCP upload controller and its behavior are unchanged.

**Source:** `app/controllers/api/v1/screenshot_images_controller.rb`, `app/services/snapshots/attach_image.rb`, `app/serializers/api/v1/contract_serializer.rb`, `config/routes.rb`, and focused controller/service/integration tests.

---
title: Snapshot REST preparation and recovery
type: log
date: 2026-07-10
---

# Snapshot REST preparation and recovery

**Action:** Added authenticated API v1 prepare and show resources for manifest-backed project snapshots.

**Contract:** The service validates version, commit, explicit-offset timestamp, bounded flat entries, page/title groups, unique viewports, expected PNG/JPEG types, content hashes, opaque file-reference hashes, and the aggregate length-prefixed manifest digest before mutation.

**Recovery:** Identical and concurrent calls converge on one transactionally created graph. Replay verifies stored metadata, group membership, viewport membership, content SHA, and expected type; mismatch returns `manifest_conflict`. Responses expose stable IDs, aggregate/image state, and a snapshot-filtered review URL without local file references.

**Authorization:** API keys stay bound to their project. OAuth create requires `mcp_write`, show requires `mcp_read`, and project membership remains mandatory.

**Source:** `app/controllers/api/v1/snapshots_controller.rb`, `app/services/snapshots/prepare_upload.rb`, `app/serializers/api/v1/contract_serializer.rb`, `config/routes.rb`, and snapshot REST/service/integration tests.

---
title: Public CLI manifest identity
type: log
date: 2026-07-10
---

# Public CLI manifest identity

**Action:** Added nullable manifest, entry, image content SHA-256, and expected content-type identities for resumable CLI snapshot preparation.

**Behavior:** Legacy and MCP-created rows remain valid without digests. Manifest-backed snapshots require uniquely identified screenshot entries and content-bound ScreenshotImages with an expected PNG/JPEG type. Snapshot state is derived as awaiting upload, processing, failed, or ready from real child attachment and processing state.

**Integrity:** Partial unique indexes protect project snapshot and snapshot entry identities without changing repeated git-commit capture semantics. Existing snapshot deletion nullification and same-project validation remain unchanged.

**Source:** `db/migrate/20260710120000_add_manifest_identity_to_snapshots.rb`, `app/models/snapshot.rb`, `app/models/screenshot.rb`, `app/models/screenshot_image.rb`, and focused model tests.

---
timestamp: 2026-07-09T14:56:01Z
slug: local-ci-bootstrap
---

**Action:** Improved local CI bootstrap and dependency checks.

**Files changed:** `bin/ci`, `bin/setup`, `bin/check_coverage`, `config/ci.rb`, `.github/workflows/ci.yml`, `.gitignore`, `Gemfile.lock`, `test/test_helper.rb`, `test/jobs/screenshot_dimension_job_test.rb`, `test/services/annotation_crop_service_test.rb`

**Notes:** `bin/ci` now installs missing gems before Rails boot, stores bundles in `vendor/bundle`, runs whitespace checks, keeps GitHub push CI aligned to `main`, and runs Go tests when `go.mod` is present. Set `REQUIRE_COVERAGE=true` to run Rails tests with SimpleCov and fail below 100% line or branch coverage via `bin/check_coverage`; coverage runs force one worker for stable measurement, and `PARALLEL_WORKERS` can override normal Rails test parallelism. The lockfile was refreshed for current `bundler-audit` advisories, Brakeman freshness, and Playwright protocol compatibility. GitHub CI installs `libvips` and compatible Playwright browsers for system tests, runs Capybara against its in-process Rails server when `CAPYBARA_RUN_SERVER=true`, serializes system tests with `PARALLEL_WORKERS=1`, and caps the system-test job at 15 minutes. System fixtures now include the seed-equivalent `test@screenote.app`, `free@screenote.app`, and `Demo Project` records expected by browser tests. Browser API/MCP helpers derive the live Capybara server URL, invitation tests inspect test mail deliveries instead of letter_opener files, and mailer preview assertions live in mailer tests; local image-processing tests skip with an explicit message when the system library is unavailable.

---
timestamp: 2026-07-09T14:54:14Z
slug: mcp-test-token-project-scope
---

**Action:** Documented the non-interactive MCP test-token endpoint and its project-scoped OAuth semantics.

**Pages updated:** `wiki/controllers/oauth-controllers.md`, `wiki/mcp-tools.md`, `wiki/routes.md`

**Source:** `app/controllers/oauth/test_tokens_controller.rb`, `config/initializers/fast_mcp.rb`, `app/tools/application_tool.rb`, `app/tools/list_projects_tool.rb`, `app/tools/create_project_tool.rb`, and `test/controllers/oauth/test_tokens_controller_test.rb`.

## [2026-07-08T19:42:13Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed command, REST API controller, route, MCP/CLI boundary, and CLI wiki coverage after the `add-a-go-cli-for-260708-edec` branch updated wiki-facing command/API surface documentation.
**Pages updated:** `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`
**Pages already current:** `wiki/api-cli.md`, `wiki/index.md`, `wiki/gaps.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `config/routes.rb`, `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/*`, `app/serializers/api/v1/contract_serializer.rb`, `app/services/api/v1/project_scope.rb`, `cmd/screenote`, `internal/cli`, and `internal/screenote`.
**Notes:** Kept wiki edits in the main checkout only. Used `qmd search` and source inspection; did not run `qmd update` or `qmd embed`.

## [2026-07-08T19:22:29Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` residual finalizer commit changed only branch-local wiki files, deleted branch-local log fragments/maintenance coverage, and simplified some CLI/API wiki wording.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/errors.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** The configured cross-project wiki path `/home/asterio/wikis/master/wiki` is absent and `qmd search` returned no matching results for the CLI/API refresh query. The branch-local wiki maintenance/log rollback still conflicts with the main-checkout wrapper instruction to add fragments and avoid direct compiled `wiki/log.md` edits.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T19:20:03Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` finalizer commit changed branch-local wiki files and removed branch-local log fragments/maintenance coverage without changing the committed CLI/API source behavior.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:README.md`, `git show add-a-go-cli-for-260708-edec:cmd/screenote/main.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/*`, `git show add-a-go-cli-for-260708-edec:internal/screenote/*`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, `git show add-a-go-cli-for-260708-edec:app/services/api/v1/project_scope.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** `qmd search` returned no matching results for the CLI/API refresh query, and the configured cross-project wiki path plus default fallback paths were absent. The branch-local maintenance/log rollback still conflicts with the main-checkout fragment-based refresh instructions, so this refresh kept the main checkout's fragment policy and did not edit compiled `wiki/log.md`.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T19:16:02Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` residual 6-review commit removed or simplified branch-local wiki details without changing the committed CLI/API source behavior.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/screenshots_controller.rb`, and current main-checkout wiki pages.
**Uncertainty:** `qmd search` returned no matching results for the CLI/API refresh query, and the configured cross-project wiki path plus default fallback paths were absent. The branch-local maintenance/log rollback still conflicts with the main-checkout fragment-based log policy.
**Notes:** Kept edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T19:14:11Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` residual 6-review commit changed only branch-local wiki files while the committed CLI/API source tree still supports the richer documented command and REST API surface.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `README.md`, `cmd/screenote/main.go`, `internal/cli/annotation.go`, `internal/cli/screenshot.go`, `internal/cli/root.go`, `internal/cli/errors.go`, `internal/screenote/client.go`, `internal/screenote/types.go`, `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/*`, `app/serializers/api/v1/contract_serializer.rb`, and `config/routes.rb`.
**Uncertainty:** `qmd search` returned no matching results for the CLI/API refresh query, and the configured cross-project wiki path remained unavailable. The branch-local wiki maintenance/log rollback conflicts with the main-checkout wrapper instruction to add fragments and avoid direct compiled `wiki/log.md` edits.
**Notes:** Kept edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T18:54:31Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` pass-02 review-fix commit edited CLI/API wiki wording, removed branch-local `wiki/log.d/` fragments, deleted branch-local `wiki/llm-wiki-maintenance.md`, and rewrote branch-local compiled `wiki/log.md`.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:cmd/screenote/main.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, `git show add-a-go-cli-for-260708-edec:app/services/api/v1/project_scope.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** The configured cross-project wiki path and default fallback paths were absent, and `qmd search` returned no matching project-wiki results. The branch-local wiki maintenance/log policy still conflicts with the main-checkout wrapper instructions, so this refresh kept the main checkout's fragment-based log policy and did not edit compiled `wiki/log.md`.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T18:51:56Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout CLI/API wiki coverage after the `add-a-go-cli-for-260708-edec` review-pass commit changed wiki-facing CLI/API wording and removed wiki maintenance artifacts from its own tree.
**Pages updated:** `wiki/api-cli.md`
**Pages verified current:** `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/gaps.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:README.md`, `git show add-a-go-cli-for-260708-edec:cmd/screenote/main.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/commands_test.go`, `git show add-a-go-cli-for-260708-edec:internal/screenote/client.go`, `git show add-a-go-cli-for-260708-edec:internal/screenote/types.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** The configured cross-project wiki path and default fallback paths were absent; `qmd search` returned no matching project-wiki results. The branch tree still conflicts with current main-checkout instructions on `wiki/log.d/` fragments and compiled `wiki/log.md`, so this refresh followed the wrapper instruction to add a fragment and avoid editing compiled `wiki/log.md`.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T18:47:28Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after inspecting the `add-a-go-cli-for-260708-edec` branch wiki commit and the committed REST/Go CLI source tree it documents.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:config/routes.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, and current main-checkout wiki pages.
**Uncertainty:** The branch commit deletes `wiki/log.d/` fragments and `wiki/llm-wiki-maintenance.md` in its own tree, but current main-checkout instructions require log fragments and wrapper-owned compiled `wiki/log.md`; recorded this policy mismatch in `wiki/gaps.md`.
**Notes:** Kept edits under `/home/asterio/Dev/screenote/wiki/` only. Used `qmd search`; did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T18:23:02Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed wiki coverage after the `add-a-go-cli-for-260708-edec` branch corrected Go CLI annotation aggregation, usage exits, upload content types, compact JSON output, and CLI docs.
**Pages created:** `wiki/api-cli.md`
**Pages updated:** `wiki/index.md`, `wiki/gaps.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, committed `internal/cli/annotation.go`, `internal/cli/root.go`, `internal/cli/screenshot.go`, `internal/cli/commands_test.go`, and committed `wiki/api-cli.md`
**Notes:** Did not edit compiled `wiki/log.md`; this fragment is for the post-commit wrapper to compile. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T15:34:48Z] refresh

**Action:** Refreshed project wiki against current LLM-wiki automation and recent git history.
**Pages created:** `wiki/llm-wiki-maintenance.md`
**Pages updated:** `wiki/index.md`, `wiki/gaps.md`
**Pages unchanged after source verification:** core architecture/model/controller/MCP pages; recent commits after the prior refresh changed LLM-wiki automation and context files, not application source behavior.
**Cross-project wiki:** `.llm-wiki/config.json` still points at `/home/asterio/wikis/master/wiki`, but that path and the default fallback main wiki paths were absent on this machine during refresh.
**QMD:** Used `qmd search` only; did not run `qmd update` or `qmd embed`.
**Source:** `.llm-wiki/config.json`, `AGENTS.md`, `CLAUDE.md`, `.llm-wiki/refresh-wiki.sh`, `.llm-wiki/post-commit-refresh.sh`, `.llm-wiki/compile-log.sh`, `.claude/settings.json`, recent `git log`, source inventory under `app/`, `config/`, `db/`, `plans/`, and `todos/`.
<!-- END GENERATED WIKI LOG FRAGMENTS -->

## 2026-04-10 -- Bootstrap

**Author:** Claude (LLM wiki bootstrap)
**Scope:** Full wiki creation from codebase analysis

### Pages created (25 total):

**Architecture (7):**
- `wiki/architecture.md` -- High-level app structure
- `wiki/data-model.md` -- ER diagram and all tables
- `wiki/schema-evolution.md` -- 21 migrations across 4 phases
- `wiki/routes.md` -- Complete route surface area
- `wiki/gems.md` -- Gem choices with rationale
- `wiki/decisions.md` -- 12 lightweight ADRs from git history
- `wiki/active-areas.md` -- Recent development activity

**Models (13):**
- `wiki/models/user.md`
- `wiki/models/project.md`
- `wiki/models/page.md`
- `wiki/models/screenshot.md`
- `wiki/models/annotation.md`
- `wiki/models/annotation-comment.md`
- `wiki/models/api-key.md`
- `wiki/models/project-membership.md`
- `wiki/models/project-invitation.md`
- `wiki/models/subscription.md`
- `wiki/models/session.md`
- `wiki/models/current.md`
- `wiki/models/application-record.md`

**Controllers (3):**
- `wiki/controllers/web-controllers.md` -- 14 web controllers
- `wiki/controllers/api-controllers.md` -- 3 API controllers
- `wiki/controllers/oauth-controllers.md` -- 3 OAuth controllers

**Services (1):**
- `wiki/services/annotation-crop-service.md`

**Meta (2):**
- `wiki/gaps.md` -- Known documentation gaps
- `wiki/index.md` -- Full page catalog

### Sources read:
- `db/schema.rb` (21 migrations, 13+ tables)
- 13 model files in `app/models/`
- 24 controller files in `app/controllers/`
- 1 service file in `app/services/`
- `config/routes.rb`
- `Gemfile`
- `CLAUDE.md`
- 109 git commits analyzed

### CLAUDE.md updated:
- Appended wiki section with structure, rules, and session protocols

## [2026-04-11] ingest

**Action:** Ingested plans/ (4 files) and todos/ (151 files) into wiki
**Pages created:** plans-and-initiatives.md, technical-debt.md, roadmap.md
**Pages updated:** active-areas.md, gaps.md, index.md
**Source:** plans/ and todos/ directories

## [2026-05-14T16:53:28Z] bootstrap

**Action:** Managed llm-wiki bootstrap from codebase and Hive registry.
**Pages created:** wiki/commands.md, wiki/dependencies.md
**Pages updated:** wiki/index.md, wiki/log.md, wiki/gaps.md, .llm-wiki/config.json, AGENTS.md, CLAUDE.md, .claude/settings.json
**QMD:** qmd missing
**Scheduler:** files written; systemctl enable failed for llm-wiki-screenote-a932fe24.timer
**Post-commit hook:** /home/asterio/Dev/screenote/.githooks/post-commit
**Source:** Codebase read + git history

## [2026-05-14T17:07:38Z] refresh

**Action:** Refreshed stale wiki pages against current source, recent git history, configured master wiki, plans, and todos.
**Pages created:** wiki/models/screenshot-image.md, wiki/mcp-tools.md
**Pages updated:** wiki/data-model.md, wiki/models/screenshot.md, wiki/models/annotation.md, wiki/services/annotation-crop-service.md, wiki/architecture.md, wiki/routes.md, wiki/controllers/api-controllers.md, wiki/controllers/web-controllers.md, wiki/schema-evolution.md, wiki/decisions.md, wiki/active-areas.md, wiki/roadmap.md, wiki/plans-and-initiatives.md, wiki/technical-debt.md, wiki/gaps.md, wiki/index.md, wiki/log.md
**Gaps found:** jobs scheduling documentation, todo/source status drift, remaining MCP delete/status/batch tools, ScreenshotImage transition cleanup
**Cross-project wiki:** searched `/home/asterio/wikis/master/wiki` and QMD results before editing
**QMD:** `screenote` collection already existed; `qmd embed` completed with CPU fallback but embedded 0 chunks and reported 3 failed chunks; `qmd update` failed with `SQLITE_READONLY`
**Source:** `git log --since=2026-04-20`, `db/schema.rb`, `app/models`, `app/controllers`, `app/tools`, `app/services`, `config/routes.rb`, `config/initializers/fast_mcp.rb`, `plans/`, `todos/`

## [2026-05-14T17:26:52Z] llm-wiki validation

**Action:** Validated managed llm-wiki bootstrap and scheduled maintenance after Hive registry bootstrap.
**Headless agent:** Codex (`.llm-wiki/config.json` has `headless_agent: "codex"`).
**Context:** `AGENTS.md` and `CLAUDE.md` contain the managed LLM WIKI block; Claude `SessionStart` prints `wiki/index.md` and recent `wiki/log.md`.
**QMD:** `qmd 2.1.0` collection update, embed, and `qmd search` succeeded for this collection after the scheduled refresh test. QMD attempted GPU first and fell back to CPU because Vulkan headers are missing.
**Scheduler:** `llm-wiki-screenote-a932fe24.timer` is enabled and active under `systemctl --user`; next run is scheduled for 2026-05-15 18:03:41 BST.
**Maintenance scripts:** `.llm-wiki/refresh-wiki.sh` and `.llm-wiki/post-commit-refresh.sh` use bounded Codex and qmd timeouts and tell headless Codex not to run `qmd update` or `qmd embed` itself.
**Source:** `systemctl --user list-timers`, `qmd update`, `qmd embed`, and collection-scoped `qmd search`.

## [2026-05-14] snapshot model

**Action:** Documented the Snapshot model and project-page snapshot filtering data model.
**Pages created:** wiki/models/snapshot.md
**Pages updated:** wiki/data-model.md, wiki/models/project.md, wiki/models/screenshot.md, wiki/index.md
**Source:** Snapshot implementation in app/models, db/schema.rb, and project page controller/view changes

## [2026-05-15] snapshot review hardening

**Action:** Clarified snapshot duplicate-commit semantics, UTC-stable labels, future timestamp validation, and model-owned project-page snapshot queries.
**Pages updated:** data-model.md, models/project.md, models/snapshot.md
**Source:** Review pass 03 fixes for the snapshot feature

## [2026-07-08] OAuth-first CLI and REST OAuth auth

**Action:** Updated API/CLI docs for OAuth-first CLI authentication and REST v1 dual bearer authentication.
**Pages updated:** wiki/api-cli.md, wiki/controllers/api-controllers.md, wiki/routes.md, wiki/log.md
**Source:** `internal/cli`, `internal/screenote`, `app/controllers/api`, `app/services/api/bearer_authenticator.rb`, controller tests

## [2026-07-09] OAuth CLI review hardening

**Action:** Hardened the OAuth CLI review findings: bounded every default HTTP path, kept saved login credentials aligned with the configured server, preserved JSON-only output when browser launch fails, masked bearer tokens from `screenote config`, and enforced owner-only permissions on existing config files.
**Pages updated:** wiki/api-cli.md, wiki/log.md
**Source:** `internal/cli`, `internal/config`, `internal/screenote`, Go regression tests

## [2026-07-09] snapshot review and current-main integration

**Action:** Re-reviewed project snapshots against current main, preserved pending-only and failed-only pages in the unfiltered project view, made empty snapshot-filter states accurate, required explicit-offset MCP timestamps, echoed snapshot linkage in capture responses, regenerated the schema so its 40-character git commit limit matches the migration, made the snapshot system test target Capybara's actual in-process server, and removed unrelated historical planning/todo artifacts from the PR.
**Pages updated:** wiki/index.md, wiki/schema-evolution.md, wiki/mcp-tools.md, wiki/models/project.md, wiki/models/snapshot.md, wiki/log.md
**Source:** `app/models/project.rb`, `app/tools/create_snapshot_tool.rb`, `app/tools/create_multi_viewport_screenshot_tool.rb`, project views, migrations, and regression tests

## [2026-07-13] public help command parity

**Action:** Updated the public help workflow after production verification so CLI project creation, annotation crop extraction, and idempotent annotation resolution are documented instead of the superseded dashboard-only and web-only limits.
**Pages updated:** wiki/active-areas.md, wiki/log.md
**Source:** `app/views/static_pages/_help_quick_start.html.erb`, `app/views/static_pages/_help_cli.html.erb`, public CLI merge `c28ac8b`
