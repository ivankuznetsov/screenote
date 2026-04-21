---
title: Roadmap
type: architecture
source: plans/, todos/, git log
created: 2026-04-11
updated: 2026-04-11
tags: [roadmap, direction, priorities]
---

# Roadmap

High-level project direction synthesized from plans, todos, and recent git history. Screenote is a working product in production -- the core loop (upload, annotate, agent reads via MCP) is complete. Development is now split between **feature expansion** and **hardening**.

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

The agent-facing API has significant gaps. Seven todos request missing tools:

- `delete_screenshot` (#054), `delete_annotation` (#055)
- `create_annotation` (#012) -- agents can't leave feedback
- `reopen_annotation` (#132), `add_annotation_comment` (#133)
- `create_project` (#098), plan status tools (#120)
- Invitation/membership tools (#153)

Batch feedback retrieval (#053) would also reduce agent round-trips.

### Data Integrity

Four separate todos for missing `on_delete` cascade strategies on foreign keys (#004, #090, #127, #137). These should be resolved in a single migration batch.

## Planned Features

### Near-term: Page/Version Hierarchy

The largest pending feature. See [[plans-and-initiatives]] for details. Introduces Project -> Page -> Version organization to replace the flat screenshot list. Prerequisite: rename `PagesController` to `StaticPagesController`.

This will significantly improve the agent feedback loop -- agents can group screenshots by page name and track iteration history.

### Near-term: Help Page Public Access + MCP Docs

Make `/help` publicly accessible, add MCP connection documentation (endpoint, OAuth, API keys), expand Claude Code quick start. Blocked by the Page/Version Phase 0 rename (both touch `PagesController`).

### Near-term: Claude Code Skill

Ship `/screenote` slash command for Claude Code. Add `image_path` parameter to `CreateScreenshotTool` to avoid base64 through context window. Independent of other plans.

### Medium-term: Performance & Scaling

- Pagination for controllers and MCP tools (#010)
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
2. **Page/Version hierarchy** -- largest UX improvement, enables better agent workflows
3. **MCP tool completeness** -- fill gaps in agent API surface
4. **Help page + Claude Code skill** -- developer experience and discoverability
5. **Performance** -- pagination, N+1 fixes, indexes
6. **Frontend conventions** -- inline styles, Stimulus patterns, accessibility

See also: [[plans-and-initiatives]], [[technical-debt]], [[active-areas]], [[gaps]]
