---
title: Plans and Initiatives
type: architecture
source: plans/ directory (4 files)
created: 2026-04-11
updated: 2026-04-11
tags: [plans, roadmap, features, initiatives]
---

# Plans and Initiatives

Summary of all active plans from the `plans/` directory. These are the major feature initiatives driving Screenote's development, ranging from foundational product vision to specific UX and developer-experience improvements.

## Product Vision

### Visual Feedback Tool for AI Agents (plans/screenote-visual-feedback-for-ai-agents.md)

**Status:** Foundational -- the "master plan" that defines the product.

Screenote's core thesis: humans leave Figma-style visual comments on screenshots, and AI agents consume those comments via MCP **with the actual cropped image region**. Three workflows:

1. **Upload screenshot** -- user uploads, annotates, agent collects via MCP
2. **Enter URL** -- server-side capture (deferred to post-launch)
3. **Agent-initiated feedback loop** -- the killer feature: agent screenshots localhost, uploads to Screenote, human annotates, agent reads cropped feedback, agent fixes, repeat

The plan covers the full technical stack (Rails 8, Annotorious v3, FastMCP, Active Storage on Rabata S3), the data model (percentage-based coordinates, point vs region annotations), MCP tool design, and four implementation phases (Foundation, Screenshots+Annotations, MCP Server, Production Polish). Most of this is already implemented -- see [[active-areas]] for current state.

**Key deferred items:** Server-side URL capture, screenshot versioning, pan/zoom, annotation threading, team collaboration, browser extension.

## Feature Initiatives

### Page/Version Hierarchy (plans/project-page-version-hierarchy.md)

**Status:** Ready to implement. Largest pending structural change.

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

**Status:** Ready to implement.

Three changes bundled together:
1. **Make help page public** -- currently behind authentication, blocking potential users from evaluating Screenote
2. **Expand Claude Code quick start** -- fix command syntax, show full feedback loop
3. **Add MCP connection documentation** -- endpoint URL, OAuth 2.1 and API key auth methods, project_id behavior differences

Also fixes: guest navigation (Help | Sign In | Get Started), logo link for guests, landing page footer help link, and the same broken-nav issue on /terms and /privacy.

Implementation: split help.html.erb into partials (quick_start, workflows, mcp), minimal CSS additions, test updates.

See also: [[controllers/web-controllers]], [[routes]]

### Claude Code Skill (plans/screenote-claude-code-skill.md)

**Status:** Ready to implement.

A SKILL.md file at `.claude/skills/screenote/SKILL.md` with two modes:
- **Capture** (`/screenote [url]`): Playwright MCP screenshots the page, uploads via `create_screenshot` with `image_path` parameter (avoids base64 through context window), returns annotation URL
- **Feedback** (`/screenote feedback`): retrieves open annotations with cropped images, formatted for Claude to act on

Prerequisite: add `image_path` parameter to `CreateScreenshotTool` (alternative to `image_base64`, reads file from disk directly).

Key decisions: no base64 through context, viewport-only screenshots (not fullPage), resolve is opt-in (ask user first), single skill with two modes.

## Dependency Map

```
Page/Version Hierarchy
  └── Requires: StaticPagesController rename (Phase 0)
  └── Affects: MCP tools, routes, views, authorization

Help Page Redesign
  └── Blocked by: Page/Version Phase 0 (both touch PagesController)
  └── Affects: layouts, routes (indirectly), tests

Claude Code Skill
  └── Requires: image_path parameter on CreateScreenshotTool
  └── Independent of other plans

Visual Feedback (master plan)
  └── Mostly implemented; remaining items feed into other plans
```

See also: [[roadmap]], [[technical-debt]], [[active-areas]]
