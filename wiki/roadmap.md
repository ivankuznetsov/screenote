---
title: Roadmap
type: architecture
source: plans/, todos/, git log
created: 2026-04-11
updated: 2026-05-14
tags: [roadmap, direction, priorities]
---

# Roadmap

High-level project direction synthesized from plans, todos, and recent git history. Screenote is a working product in production -- the core loop (upload, annotate, agent reads via MCP) is complete, and recent work extended it to multi-viewport responsive review.

## Recently Completed

Based on [[active-areas]] and completed todos:

- **Annotation comment threads** with resolve/reopen workflow (PR #18)
- **Hourly digest email notifications** for resolved annotations (PR #24, #25)
- **Collaborator autocomplete** on invite field (PR #26)
- **Stripe billing integration** with free/pro tiers and webhook handling (PR #11)
- **OAuth 2.1 provider** for MCP with Doorkeeper, DCR, and PKCE
- **Help page overhaul** -- data-driven tool cards, extracted CSS, banner CLS fix
- **MCP tool improvements** -- fixed N+1 in list_screenshots, double JSON serialization, error message leakage, rate limit race condition
- **CSS architecture** -- split monolithic stylesheet, hardcoded colors replaced with variables, BEM naming fixes
- **E2E test infrastructure** -- Capybara + Playwright setup, page object model, testid coverage
- **Welcome email** and **branded error pages**
- **Stripe webhook hardening** -- idempotency ledger, locked model-owned transitions, item-level period end handling
- **Multi-viewport screenshots** -- ScreenshotImage child model, viewport switcher, viewport-scoped annotations, multi-viewport MCP signed-upload flow
- **Public help/MCP docs** -- StaticPagesController, partialized help page, dynamic MCP tool reference

~90 todos marked complete across security fixes, CSS cleanup, MCP improvements, Stripe hardening, and test quality.

## In Progress / Ready

### Security Hardening (highest priority)

The OAuth 2.1 implementation has 7 ready P1/P2 security items that should be addressed as a batch:

- IDOR in consent flow (#082)
- Silent failures in token validation (#085, #086)
- Missing rate limits on DCR and OAuth MCP (#087, #088)
- Exposed admin routes (#089)
- Arbitrary redirect URIs (#094)

Additionally: fetch redirect injection (#143), silent catch-all error swallowing (#144), and file upload validation (#001).

### MCP Tool Completeness

The agent-facing API has narrowed gaps. Source now includes `create_annotation`, `reopen_annotation`, `add_annotation_comment`, `create_project`, and collaboration tools, despite some older todo filenames/frontmatter still suggesting otherwise.

Remaining visible gaps:

- `delete_screenshot` (#054), `delete_annotation` (#055)
- plan/status tools (#120)
- batch feedback retrieval (#053)

Batch feedback retrieval (#053) would reduce agent round-trips. See [[mcp-tools]].

### Data Integrity

Four separate todos for missing `on_delete` cascade strategies on foreign keys (#004, #090, #127, #137). These should be resolved in a single migration batch.

## Planned Features

### Near-term: Multi-Viewport Cleanup

Finish follow-up work around the new ScreenshotImage architecture: remove or retire transitional `Screenshot#image` assumptions once safe, resolve the PR-specific todo cluster (#166-#178), and keep MCP/create flows aligned with per-viewport semantics.

### Near-term: Claude Code Skill

Ship `/screenote` slash command for Claude Code. The older plan asks for `image_path` support on `CreateScreenshotTool`; current source also offers signed-upload flows that avoid base64 through MCP context.

### Medium-term: Performance & Scaling

- Finish pagination coverage for browser controllers and any remaining agent surfaces (#010)
- N+1 query fixes across screenshot grid and MCP (#006, #128)
- Debounce `touch_last_used!` (#011)
- Missing database indexes (#018, #091)
- Subquery optimization (#150)

### Long-term (deferred)

From the master plan's "future phases":

- **Server-side URL capture** -- headless Chrome for public URL screenshots
- **Pan/zoom** on annotation canvas
- **Annotation threading/replies** beyond current comment system
- **Browser extension** for one-click screenshot + upload
- **Rethink OAuth project scoping** (#108) -- fundamental architecture question about user-scoped vs project-scoped tokens

## Priority Order

1. **Security hardening** -- OAuth IDOR, rate limits, fetch redirect injection
2. **Multi-viewport cleanup** -- stabilize ScreenshotImage transition and remove legacy assumptions
3. **MCP tool completeness** -- fill remaining delete/status/batch gaps in agent API surface
4. **Claude Code skill** -- developer experience and discoverability
5. **Performance** -- pagination, N+1 fixes, indexes
6. **Frontend conventions** -- inline styles, Stimulus patterns, accessibility

See also: [[plans-and-initiatives]], [[technical-debt]], [[active-areas]], [[gaps]]
