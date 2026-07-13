---
title: Roadmap
type: architecture
source: plans/, todos/, git log
created: 2026-04-11
updated: 2026-07-13
tags: [roadmap, direction, priorities]
---

# Roadmap

High-level project direction synthesized from plans, todos, recent git history, and current product decisions. Screenote is a working product in production: agents publish captures and retrieve visual feedback through the public Screenote CLI, while humans annotate in the browser. The server still exposes MCP compatibility, but its sunset is a separate migration task rather than the public onboarding path.

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
- **Public CLI and snapshot command** -- separate public repository, manifest-driven resumable uploads, OAuth login, and stable JSON contracts
- **Headless OAuth device login** -- RFC 8628 approval for SSH, tmux, containers, and agents without callback forwarding
- **Public help/CLI docs** -- CLI-first landing page, dashboard banner, welcome email, and OAuth-only installation guidance

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

### CLI Adoption And MCP Sunset

The public CLI is the supported agent and automation surface. Remaining CLI gaps include snapshot-scoped feedback retrieval, annotation resolve/reopen, and wider distribution beyond `go install`; see [[api-cli]].

MCP remains in the server for compatibility while a separately scoped sunset task removes clients, metadata, and runtime code safely. Do not expand the MCP tool surface as part of CLI work. Historical tool coverage remains documented in [[mcp-tools]] until that migration lands.

### Data Integrity

Four separate todos for missing `on_delete` cascade strategies on foreign keys (#004, #090, #127, #137). These should be resolved in a single migration batch.

## Planned Features

### Near-term: Multi-Viewport Cleanup

Finish follow-up work around the new ScreenshotImage architecture: remove or retire transitional `Screenshot#image` assumptions once safe, resolve the PR-specific todo cluster (#166-#178), and keep REST/CLI capture flows aligned with per-viewport semantics.

### Near-term: Claude Code Skill

Reframe the older `/screenote` slash-command plan around invoking the public CLI and `screenote snapshot --manifest`. New integrations should not depend on MCP-specific `image_path` or signed-upload tools.

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
3. **CLI adoption and MCP sunset** -- complete public distribution and remove MCP through its separately scoped migration
4. **Agent integrations** -- build skills and automation on the public CLI contract
5. **Performance** -- pagination, N+1 fixes, indexes
6. **Frontend conventions** -- inline styles, Stimulus patterns, accessibility

See also: [[plans-and-initiatives]], [[technical-debt]], [[active-areas]], [[gaps]]
