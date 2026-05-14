---
title: Active Areas
type: architecture
source: git log --since="6 months ago"
created: 2026-04-10
updated: 2026-05-14
tags: [active, development, roadmap, recent]
---

# Active Areas

TLDR: Recent development focused on multi-viewport screenshot capture, Stripe webhook hardening, help/MCP documentation, and LLM wiki automation. The core product loop now supports upload -> per-viewport annotation -> agent reads cropped feedback.

Source: `git log --all --oneline --since="6 months ago"` (112 commits)

## Recently Completed (Feb-Apr 2026)

### Multi-Viewport Screenshots (PR #28, #29, #30)
- Added `ScreenshotImage` child model with desktop/tablet/mobile viewport enum
- Added `annotations.viewport` and per-viewport annotation filtering
- Moved readers to `ScreenshotImage`, added deploy-time backfill, and kept legacy `Screenshot#image` only for transition/rollback paths
- Added `create_multi_viewport_screenshot` MCP tool and viewport switcher route `/screenshots/:id/viewports/:viewport`
- Commits: `7f413b2`, `9786e6e`, `85d22c3`

### Stripe Webhook Hardening
- Added `StripeWebhookEvent` idempotency ledger
- Moved subscription transition logic to `Subscription`
- Scoped subscription update/delete webhooks to the tracked Stripe subscription id
- Reads `current_period_end` from Stripe subscription items for API 2026-01-28
- Commits: `e6d620a`, `cd99da2`, `898fb4c`

### Help and MCP Documentation
- Static pages now live under `StaticPagesController`
- `/help` is public and split into quick start, workflows, and MCP partials
- Help page dynamically renders tools from `ApplicationTool.descendants`
- Source: `app/controllers/static_pages_controller.rb`, `app/views/static_pages/_help_mcp.html.erb`

### LLM Wiki Automation
- Added managed AGENTS/CLAUDE wiki instructions, `.llm-wiki/config.json`, refresh scripts, and post-commit hook wiring
- Current config uses Codex as headless agent and `/home/asterio/wikis/master/wiki` as the master wiki path

### Annotation Comment Threads (PR #18)
- Full resolve/reopen workflow with comment threads
- Both users and API keys (agents) can resolve/reopen
- Transactional operations with audit trail
- Commits: `f59b764`, `1a16456`, `701230e`, `c6a5794`

### Hourly Digest Notifications (PR #24, #25)
- Email digests for resolved annotations
- Per-author notification tracking to prevent duplicates
- Fixed edge cases with retry handling
- Commits: `9f50825`, `c2ca60f`, `980dd3d`, `745171d`

### Collaborator Autocomplete (PR #26)
- Autocomplete on invite email field suggesting users from other shared projects
- Rate-limited, owner-only
- Commit: `c425b8b`

### Welcome Email on Sign-up (PR #23)
- Sends welcome email to new users on first registration
- Commit: `ddc0d73`

### Project Thumbnail Previews (PR #20, #22)
- Thumbnail previews on project index cards and page cards
- Uses latest ready screenshot from each page
- Commits: `407fef5`, `25d5cf0`

### Branded Error Pages
- Custom 404 page with dark theme
- Replaced default Rails error pages
- Commits: `cba5086`, `0c921dc`

### OAuth Token Expiry Fix (PR #19)
- Changed MCP OAuth token expiry from 1 hour to 1 year
- Commits: `9186f9f`

## Current Architecture Maturity

| Area | Status |
|------|--------|
| Core annotation workflow | Stable, production-ready |
| Multi-viewport screenshot workflow | Recently added, maturing |
| MCP integration (OAuth 2.1/API keys) | Stable, production-ready |
| REST API (v1) | Stable, minimal surface |
| Team collaboration | Stable, recently polished |
| Billing (Stripe) | Recently hardened |
| Email notifications | Recently added, maturing |
| Admin dashboard | Basic stats only |

## Likely Next Areas

Cross-referenced with `plans/` (6 files), `todos/` (176 files), and current source:

1. **Security hardening (OAuth)** -- The todo set still highlights IDOR in consent flow (#082), token validation hardening (#085, #086), and project scoping (#108). Source now appears to address several older rate-limit/admin-route/DCR redirect findings; see [[technical-debt]] for source/todo drift.

2. **Multi-viewport follow-up** -- Clean up transitional `Screenshot#image` path and PR review todos after ScreenshotImage proves stable.

3. **MCP tool completeness** -- Source now includes create/reopen/comment annotation tools, create_project, and invitation/membership tools. Remaining visible gaps are delete_screenshot (#054), delete_annotation (#055), batch feedback retrieval (#053), and plan/status or usage-limit tools (#120). See [[mcp-tools]].

4. **Claude Code skill** -- `/screenote` slash command for capture + feedback retrieval. Requires file-path upload support or use of the signed-upload/multi-viewport tools.

5. **Frontend convention cleanup** -- Pending todos cover inline styles, imperative JS, CDN dependencies, px vs rem, missing ARIA attributes.

6. **Notification expansion** -- Digest notifications infrastructure is new; likely to expand to more event types.

See also: [[decisions]], [[gaps]], [[plans-and-initiatives]], [[technical-debt]], [[roadmap]]
