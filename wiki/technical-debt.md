---
title: Technical Debt
type: architecture
source: todos/ directory, app/tools/, config/initializers/fast_mcp.rb
created: 2026-04-11
updated: 2026-05-14
tags: [technical-debt, code-quality, todos, deferred-work]
---

# Technical Debt

Extracted from 176 todo files in `todos/`, then cross-checked against current source for areas that changed after the original wiki. Todos have three statuses in frontmatter: **pending**, **ready**, and **complete**. Some filenames include `complete` even when frontmatter still says `status: pending`; source files are treated as authoritative for wiki claims.

## Summary

| Status | P1 | P2 | P3 | Total |
|--------|----|----|-----|-------|
| Pending | 19 | 48 | 31 | 98 |
| Ready | 6 | 20 | 11 | 37 |
| Complete | 8 | 20 | 13 | 41 |

## Security (Critical)

### P1 -- Must Fix

- **#001** File upload validation. Source now validates content type and size on `ScreenshotImage` and legacy `Screenshot`; verify remaining upload paths before closing the todo.
- **#003** Thread-local MCP state not cleaned up after requests (leak risk)
- **#004** Foreign keys on `resolved_by` columns block deletions (no cascade)
- **#082** (ready) IDOR: `project_id` tampering in OAuth consent flow
- **#143** (ready) `fetch()` follows `require_owner!` redirect, injects full HTML into dropdown

### P2 -- Should Fix

- **#008** DNS rebinding protection: `config.hosts` not enabled
- **#009** Content Security Policy not configured
- **#015** Missing length validations on comment/name/title fields
- **#087** (ready) No rate limiting on DCR endpoint. Source now shows a 10/hour IP rate limit in `Oauth::RegistrationsController`; todo status may be stale.
- **#088** (ready) No rate limiting on OAuth-authenticated MCP requests. Source now shows token-level MCP rate limiting in `ProjectAuthTransport`; todo status may be stale.
- **#089** (ready) Doorkeeper admin routes exposed. Routes now call `skip_controllers :applications, :authorized_applications, :token_info`; todo status may be stale.
- **#094** (ready) DCR allows arbitrary redirect URI domains. Source now restricts redirect URIs to localhost/127.0.0.1/::1; todo status may be stale.
- **#131** `annotation_params` still permits `:status` -- bypasses comment thread mechanism
- **#148** (ready) Rate limit missing `with:` handler and `by:` user scoping

### P3

- **#017** Rate limit rejection returns silent failure, not 429
- **#021** JavaScript interpolated values in Honeybadger snippet not escaped

## Data Integrity

### P1

- **#005** Migration down method should raise `IrreversibleMigration`
- **#127** Missing `on_delete` for FKs on annotation_comments
- **#130** No guard against reopening already-open annotations

### P2

- **#014** `resolved_by_user` not set when resolving via web UI
- **#090** (ready) Missing `on_delete` strategies on Doorkeeper foreign keys
- **#137** `annotation_id` FK missing `on_delete: :cascade`
- **#140** `has_author` validation allows both user AND api_key simultaneously

## Performance

### P2

- **#006** N+1 queries in screenshot grid and MCP tools
- **#010** Pagination gaps. `list_annotations` and `list_screenshots` now paginate; browser controllers may still need coverage.
- **#011** `touch_last_used!` fires on every MCP request (no debounce)
- **#018** (p3) Missing composite index on `screenshots(project_id, created_at)`
- **#053** N+1 tool calls for annotation feedback retrieval (batch MCP)
- **#091** (ready) Missing indexes on `project_id` in Doorkeeper tables
- **#128** N+1 query in `ApplicationTool.project_annotations` for comments count
- **#150** (ready) Three preliminary queries should be subqueries

## MCP / Agent-Native

### P2

- **#002** (p1) No structured error handling in MCP tools. Source now has `ApplicationTool#with_error_handling`; verify every tool uses it consistently before closing.
- **#012** `CreateAnnotationTool` exists in source, but todo frontmatter still says pending
- **#053** Batch feedback retrieval needed (avoid N+1 tool calls)
- **#054** Missing `delete_screenshot` MCP tool
- **#055** Missing `delete_annotation` MCP tool
- **#098** (ready) Empty projects consent form + missing `create_project` MCP tool; source now has `CreateProjectTool`, but the consent-form concern may remain
- **#120** (ready) No agent-facing MCP tools for plan status or limits
- **#132** `ReopenAnnotationTool` exists in source, but todo frontmatter still says pending
- **#133** `AddAnnotationCommentTool` exists in source, but todo frontmatter still says pending
- **#153** Invitation/membership tools exist in source and todo frontmatter says complete

### P3

- **#017** Rate limit 429 response for agents
- **#057** SKILL.md missing usage instructions for resolve/create annotation
- **#058** `create_screenshot` response missing status field

## Architecture / Rails Conventions

### P2

- **#007** Annotation status filtering happens in view, not controller
- **#013** Stimulus controllers build DOM imperatively instead of using Turbo
- **#016** Annotorious CSS loaded from CDN (should be vendored)
- **#108** (ready) Rethink OAuth project scoping: user-scoped vs single-project
- **#134** `sort_by` in view should use association default scope
- **#145** (ready) Partial uses `@suggestions` instance variable instead of locals
- **#146** (ready) Imperative click listeners instead of Stimulus `data-action`

### P3

- **#019** Extract annotation serialization helper to DRY tools
- **#020** Remove YAGNI code and low-value tests
- **#022** Use Rails route helpers for `APP_HOST` instead of `ENV.fetch`
- **#099** (ready) Replace `form_tag` with `form_with` in consent view
- **#100** (ready) Remove dead code in doorkeeper.rb initializer
- **#101** (ready) DCR controller should inherit `ActionController::API`
- **#139** Serialization duplication between `ApplicationTool` and API controller
- **#141** "reopen" vs "unresolve" vocabulary split in codebase

## OAuth Implementation (082-108)

A cluster of 27 todos from the OAuth 2.1/Doorkeeper implementation review. Several have source-level fixes visible in `config/initializers/fast_mcp.rb`, `config/routes.rb`, and `app/controllers/oauth/registrations_controller.rb`, but the todo frontmatter has not been reconciled. The most important still-open architectural question is:

- **#108** (p2, ready) Fundamental question: should OAuth be user-scoped or project-scoped?

Still verify #082, #083, #085, and #086 directly before declaring the OAuth cluster closed. Current source shows absolute `WWW-Authenticate` resource metadata, logging/rescue around token validation, and Honeybadger reporting, but this wiki refresh did not audit the full consent-flow authorization behavior.

## Multi-Viewport Follow-Up

The multi-viewport PR added a new todo cluster (#166-#178). Source inspection confirms the main architecture is implemented (`ScreenshotImage`, `annotations.viewport`, viewport switcher, and `create_multi_viewport_screenshot`), but follow-up concerns remain or need reconciliation:

- **#166** upload save-with-validation: source now calls `screenshot_image.save!` after attach in `Api::ScreenshotUploadsController`; todo frontmatter still says pending.
- **#167** backfill reverse rake task: migration has rollback helpers on `ScreenshotImage`; verify operator-facing rake task coverage before closing.
- **#168** remove default on `annotations.viewport`: schema still has default 0.
- **#172** remove/delegate legacy `Screenshot#image`: source still keeps the legacy parent attachment path for transition/rollback.
- **#177** require viewport when multi-variant: source enforces this in `CreateAnnotationTool`; todo frontmatter still says pending.

## CSS / Frontend

### P2

- **#129** Inline styles and JS `style.display` manipulation violate project conventions
- **#135** Resolve/reopen button style asymmetry
- **#147** (ready) Dropdown width spans over invite button

### P3

- **#151** (ready) CSS uses px values instead of rem and CSS variables
- **#152** (ready) Missing ARIA combobox attributes

## Testing

### P2

- **#056** Missing test coverage for `CreateScreenshotTool`
- **#149** (ready) Missing tests: SQL injection, self-exclusion, pending invitation exclusion

### P3

- **#102** (ready) Extract shared OAuth test helpers
- **#142** Fixture uses magic number for action enum

## Patterns

1. **Security debt is concentrated in OAuth/MCP auth** -- the IDOR (#082), silent failures (#085), and missing rate limits (#087, #088) should be prioritized together.
2. **MCP tool surface is mostly filled but still incomplete** -- current tools cover create/reopen/comment annotations, projects, pages, screenshots, and collaboration. Missing from source: delete screenshot, delete annotation, plan/status or usage-limit tools, and batch feedback retrieval. See [[mcp-tools]].
3. **Foreign key cascades are a recurring theme** -- #004, #090, #127, #137 all address missing `on_delete` strategies.
4. **Frontend conventions are inconsistent** -- inline styles (#129), imperative JS (#146), CDN dependencies (#016), px values (#151).

See also: [[plans-and-initiatives]], [[roadmap]], [[gaps]], [[mcp-tools]]
