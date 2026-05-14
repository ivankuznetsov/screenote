---
title: Wiki Changelog
type: architecture
source: wiki/
created: 2026-04-10
updated: 2026-04-11
tags: [log, changelog]
---

# Wiki Changelog

Append-only log of all wiki operations.

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
