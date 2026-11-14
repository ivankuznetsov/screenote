---
timestamp: 2026-11-11T09:30:00Z
slug: project-audit-fixes-wave-2
---

## [2026-11-11T09:30:00Z] Project audit fixes, second wave

**Action:** Applied the remaining audit findings on branch `chore/project-audit-fixes`.

**Repository and operations:**

- Removed the transitional in-repo Go CLI (`cmd/`, `internal/`, `go.mod`, `go.sum`, `.goreleaser.yml`) and its CI, Dependabot, release-validator, and notices references. Go tests run only against the public `screenote-cli` checkout.
- `THIRD_PARTY_NOTICES.md` versions regenerated from `Gemfile.lock`.
- `cli-contract-main.yml` installs libvips before booting Rails.
- Dropped unread env entries (`RAILS_SERVE_STATIC_FILES`, `RAILS_LOG_TO_STDOUT`) and `POSTGRES_PASSWORD` from the app container's secrets; the db accessory keeps it.
- `.dockerignore` excludes `test/`, `wiki/`, `todos/`, `plans/`, `raw/`, and agent tooling directories.

**Data model:**

- Removed the legacy `Screenshot#image` attachment, its upload token, the backfill/rollback helpers and rake tasks. Migration `20260421114232` is a no-op with an irreversible `down`. `screenshots.width`/`height` are ignored columns, to be dropped in a following release.
- Migration `20261111120000`: adds `screenshots(page_id, created_at)`, drops the mis-named `created_at`-only index and eight redundant prefix indexes, and makes `annotations.comment` NOT NULL (aborts with IDs if NULL rows exist).
- `Page#latest_screenshot` uses a per-page NOT EXISTS predicate ordered by `created_at`, then `id`.
- `ReconcileScreenshotProcessingJob` scans only `ScreenshotImage.needing_processing`; the image-attachment re-warming query now reaches unwarmed rows.
- Annotations must have both region dimensions or neither.

**MCP and REST:**

- `remove_project_member` requires a user-scoped principal with write scope.
- MCP list/create tools reuse the REST serializer and gain fields (`viewports`, `screenshot_count`, `attachments`); no keys removed.
- Unknown `status`/`viewport` filter values return 422 `validation_failed` (REST) or `invalid_arguments` (MCP).
- REST `viewports` are in enum order (desktop, tablet, mobile).
- List endpoints and tools use grouped counts instead of per-row queries.
- Dynamic client registration sweeps stale clients inline only at capacity; OAuth rate limiters use `Screenote::RateLimitStore`.

**Web:**

- Shared controller concerns: `PrivateResponseHeaders` (always sends `Pragma: no-cache`), `FailClosedRateLimiting`, `MailDeliveryRequired`, `InvitationLinkStatus`, `Oauth::PrincipalSelection`.
- Failed OAuth consent keeps the selected project; the Authorize form sends `response_mode`.
- `User#access_active?` and `#active_for_authentication?` removed in favour of `active?`.
- Non-production default base URL is `http://localhost:3005`.
- Stylesheets load once per page via `stylesheet_link_tag :app`; the invitation acceptance page is styled; the sidebar author marker is a span; zoomed attachments scroll to every edge.

**Pages updated:** `wiki/testing-and-ci.md`, `wiki/self-hosting.md`, `wiki/commands.md`, `wiki/api-cli.md`, `wiki/models/user.md`, `wiki/models/screenshot.md`, `wiki/models/screenshot-image.md`, `wiki/mcp-tools.md`.

**Uncertainty:** Frontend changes were not checked in a browser and system tests were not run.
