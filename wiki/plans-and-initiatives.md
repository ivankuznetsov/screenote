---
title: Plans and Initiatives
type: architecture
source: plans/ and docs/plans/
created: 2026-04-11
updated: 2026-08-05
tags: [plans, roadmap, features, initiatives]
---

# Plans and Initiatives

Summary of all active plans from the `plans/` directory. These are the major feature initiatives driving Screenote's development, ranging from foundational product vision to specific UX and developer-experience improvements. Some plans predate implemented code; source files remain authoritative when plan text diverges.

## Product Vision

### Visual Feedback Tool for AI Agents (plans/screenote-visual-feedback-for-ai-agents.md)

**Status:** Foundational product history. Its MCP delivery design predates the public CLI, which is now the supported agent and automation surface.

Screenote's core thesis remains: humans leave Figma-style visual comments on screenshots, and AI agents consume those comments with the actual cropped image region. The original plan specified MCP; current onboarding and new integrations use the public Screenote CLI. Three workflows:

1. **Upload screenshot** -- user uploads, annotates, agent collects via MCP
2. **Enter URL** -- server-side capture (deferred to post-launch)
3. **Agent-initiated feedback loop** -- the killer feature: agent screenshots localhost, uploads to Screenote, human annotates, agent reads cropped feedback, agent fixes, repeat

The plan covers the full technical stack (Rails 8, Annotorious v3, FastMCP, Active Storage on Rabata S3), the data model (percentage-based coordinates, point vs region annotations), MCP tool design, and four implementation phases (Foundation, Screenshots+Annotations, MCP Server, Production Polish). Most of this is already implemented -- see [[active-areas]] for current state.

**Key deferred items:** Server-side URL capture, screenshot versioning, pan/zoom, annotation threading, team collaboration, browser extension.

## Feature Initiatives

### Self-Hosted Source Release (`docs/plans/2026-08-05-001-feat-self-hosted-source-release-plan.md`)

**Status:** Implemented in source; external release infrastructure and exact qualification remain pending.

Defines Screenote's O'Saasy distribution under Future Spin Ltd: one public repository, a prebuilt single-container SQLite edition with an unlimited core, optional S3-compatible storage, atomic token-secured administrator bootstrap, closed registration, and project-scoped invitations. GitGuardian gates the initial history, every protected default-branch update, and source/image releases. Publication requires only the documented technical readiness checks and the protected release-environment approval.

See also: [[self-hosting]], [[architecture]], [[dependencies]]

### Multi-Viewport Screenshots (plans/multi-viewport-screenshots.md)

**Status:** Mostly implemented in commits `7f413b2`, `9786e6e`, and `85d22c3`.

The plan introduced the current mental model: one [[models/screenshot]] is one logical capture event, and each capture has one or more [[models/screenshot-image]] rows for desktop/tablet/mobile renderings. Annotations belong to a `(screenshot, viewport)` pair.

Source inspection confirms the child model, `annotations.viewport`, viewport route, Turbo frame switcher, and `create_multi_viewport_screenshot` signed-upload tool are present. The plan's proposed replacement of `CreateScreenshotTool` with a single `viewports: [{ image_path: ... }]` schema did not land exactly as written; current source keeps the base64 `create_screenshot` tool and adds separate signed-upload tools.

### Page/Version Hierarchy (plans/project-page-version-hierarchy.md)

**Status:** Implemented before this refresh for the Project -> Page -> Screenshot hierarchy; the plan remains useful historical design context.

Replaces the flat Project -> Screenshots structure with **Project -> Page -> Version**. A "Page" represents a logical screen (e.g., "Login", "Dashboard"), and each page has ordered versions (screenshots with timestamps).

Key decisions:
- Keep `screenshots` table name (versions are screenshots with a `page_id` FK)
- Remove direct `project_id` from screenshots, use `has_many :through`
- Phase 0 prerequisite: rename `PagesController` to `StaticPagesController`
- Shallow nested routes (max 2 levels)
- MCP: `create_screenshot` gets optional `page_name` for auto-grouping; new `list_pages` tool

Four implementation phases: (0) Rename static controller, (1) Models/migrations, (2) Controllers/routes, (3) Views/UI, (4) MCP tools. Includes reversible migration with backfill strategy.

See also: [[models/page]], [[models/screenshot]], [[data-model]]

### Help Page Redesign (plans/help-page-redesign.md)

**Status:** Implemented in current source.

Current source has `StaticPagesController`, public `/help`, extracted static-page partials, guest nav, and CLI/OAuth/snapshot guidance. The original plan bundled:
1. **Make help page public** -- currently behind authentication, blocking potential users from evaluating Screenote
2. **Expand Claude Code quick start** -- fix command syntax, show full feedback loop
3. **Add MCP connection documentation** -- historical requirement, superseded on public pages by OAuth-only CLI installation and device-login guidance

Also fixes: guest navigation (Help | Sign In | Get Started), logo link for guests, landing page footer help link, and the same broken-nav issue on /terms and /privacy.

Current implementation: partialized CLI quick start, workflows, command reference, OAuth browser/device login, and test coverage. MCP remains a server compatibility surface pending its separately scoped sunset, not a public help-page path.

See also: [[controllers/web-controllers]], [[routes]]

### Claude Code Skill (plans/screenote-claude-code-skill.md)

**Status:** Design requires revision before implementation. A future skill should invoke the public CLI rather than add new MCP coupling.

A SKILL.md file at `.claude/skills/screenote/SKILL.md` with two modes:
- **Capture** (`/screenote [url]`): Playwright MCP screenshots the page, uploads via `create_screenshot` with `image_path` parameter (avoids base64 through context window), returns annotation URL
- **Feedback** (`/screenote feedback`): retrieves open annotations with cropped images, formatted for Claude to act on

Prerequisite: add `image_path` parameter to `CreateScreenshotTool` (alternative to `image_base64`, reads file from disk directly).

Current public CLI provides `screenote snapshot --manifest` for file-based, resumable capture publishing. Reframe the skill around that contract rather than adding `image_path` to MCP tools.

Key decisions: no base64 through context, viewport-only screenshots (not fullPage), resolve is opt-in (ask user first), single skill with two modes.

## Dependency Map

```
Page/Version Hierarchy
  └── Implemented: StaticPagesController + Project -> Page -> Screenshot

Help Page Redesign
  └── Implemented: public help + OAuth CLI docs + partials

Claude Code Skill
  └── Requires: reframe historical MCP design around the public CLI
  └── Independent of other plans

Multi-Viewport Screenshots
  └── Implemented: ScreenshotImage + viewport switcher + MCP multi-viewport upload
  └── Follow-up: remove transitional Screenshot image assumptions when safe

Visual Feedback (master plan)
  └── Mostly implemented; remaining items feed into other plans

Self-Hosted Source Release
  └── Product and implementation contracts reviewed; execution pending
  └── Enables: public source and prebuilt container distribution
  └── Shares: GitGuardian policy with a later cross-repository rollout
```

See also: [[roadmap]], [[technical-debt]], [[active-areas]]
