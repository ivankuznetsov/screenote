---
timestamp: 2026-11-11T00:15:00Z
slug: project-audit-fixes
---

## [2026-11-11T00:15:00Z] Project audit fixes

**Action:** Whole-project audit of `main` at `b70a7ae3`; applied the verified fixes on branch `chore/project-audit-fixes`.

**Behaviour changes:**

- Stripe webhooks: a retryable 5xx response now removes the `StripeWebhookEvent` idempotency row, so Stripe's redelivery is processed instead of answered "already processed".
- `Annotation#reopen!` takes the row lock like `resolve!`.
- `Page.find_or_create_by_name!` recovers from a concurrent create that fails the uniqueness validation, not only the unique index.
- `ScreenshotDimensionJob` and `ScreenshotThumbnailJob` discard jobs whose screenshot image was deleted.
- Expired sessions are deleted daily (`clear_expired_sessions` in `config/recurring.yml`).
- REST and MCP `not_found` errors no longer include the SQL scope from `RecordNotFound#message`.
- `Api::ScreenshotUploadsController` error bodies always carry `code`.
- MCP: `create_screenshot_upload` creates the screenshot and its desktop image in one transaction; `create_multi_viewport_screenshot` returns `invalid_arguments` for a malformed `viewports` value.
- CSP: removed the unused jsdelivr allowances; `connect-src` allows `https://api.honeybadger.io` when hosted monitoring is on.
- CSS: the dismissed CLI banner no longer flashes; the landing install command gets its intended styling.

**Removed:** `bin/mcp` (crashed on removed `Current` attributes), `app/views/rails_simple_auth/**` and `app/views/pwa/**` (no routes), `.kamal/hooks/*.sample`, unused scopes `Session.recent`, `ImageAttachment.drafts`, `OauthDeviceGrant.expired`, and unused test helpers.

**Pages updated:** `wiki/models/session.md`, `wiki/gaps.md`.
