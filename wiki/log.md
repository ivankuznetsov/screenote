# Wiki Changelog

Append-only log of all wiki operations.

<!-- BEGIN GENERATED WIKI LOG FRAGMENTS -->
## [2026-07-08T19:42:13Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed command, REST API controller, route, MCP/CLI boundary, and CLI wiki coverage after the `add-a-go-cli-for-260708-edec` branch updated wiki-facing command/API surface documentation.
**Pages updated:** `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`
**Pages already current:** `wiki/api-cli.md`, `wiki/index.md`, `wiki/gaps.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `config/routes.rb`, `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/*`, `app/serializers/api/v1/contract_serializer.rb`, `app/services/api/v1/project_scope.rb`, `cmd/screenote`, `internal/cli`, and `internal/screenote`.
**Notes:** Kept wiki edits in the main checkout only. Used `qmd search` and source inspection; did not run `qmd update` or `qmd embed`.

## [2026-07-08T19:22:29Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` residual finalizer commit changed only branch-local wiki files, deleted branch-local log fragments/maintenance coverage, and simplified some CLI/API wiki wording.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/errors.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** The configured cross-project wiki path `/home/asterio/wikis/master/wiki` is absent and `qmd search` returned no matching results for the CLI/API refresh query. The branch-local wiki maintenance/log rollback still conflicts with the main-checkout wrapper instruction to add fragments and avoid direct compiled `wiki/log.md` edits.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T19:20:03Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` finalizer commit changed branch-local wiki files and removed branch-local log fragments/maintenance coverage without changing the committed CLI/API source behavior.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:README.md`, `git show add-a-go-cli-for-260708-edec:cmd/screenote/main.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/*`, `git show add-a-go-cli-for-260708-edec:internal/screenote/*`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, `git show add-a-go-cli-for-260708-edec:app/services/api/v1/project_scope.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** `qmd search` returned no matching results for the CLI/API refresh query, and the configured cross-project wiki path plus default fallback paths were absent. The branch-local maintenance/log rollback still conflicts with the main-checkout fragment-based refresh instructions, so this refresh kept the main checkout's fragment policy and did not edit compiled `wiki/log.md`.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T19:16:02Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` residual 6-review commit removed or simplified branch-local wiki details without changing the committed CLI/API source behavior.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/screenshots_controller.rb`, and current main-checkout wiki pages.
**Uncertainty:** `qmd search` returned no matching results for the CLI/API refresh query, and the configured cross-project wiki path plus default fallback paths were absent. The branch-local maintenance/log rollback still conflicts with the main-checkout fragment-based log policy.
**Notes:** Kept edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T19:14:11Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` residual 6-review commit changed only branch-local wiki files while the committed CLI/API source tree still supports the richer documented command and REST API surface.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `README.md`, `cmd/screenote/main.go`, `internal/cli/annotation.go`, `internal/cli/screenshot.go`, `internal/cli/root.go`, `internal/cli/errors.go`, `internal/screenote/client.go`, `internal/screenote/types.go`, `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/*`, `app/serializers/api/v1/contract_serializer.rb`, and `config/routes.rb`.
**Uncertainty:** `qmd search` returned no matching results for the CLI/API refresh query, and the configured cross-project wiki path remained unavailable. The branch-local wiki maintenance/log rollback conflicts with the main-checkout wrapper instruction to add fragments and avoid direct compiled `wiki/log.md` edits.
**Notes:** Kept edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T18:54:31Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` pass-02 review-fix commit edited CLI/API wiki wording, removed branch-local `wiki/log.d/` fragments, deleted branch-local `wiki/llm-wiki-maintenance.md`, and rewrote branch-local compiled `wiki/log.md`.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:cmd/screenote/main.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, `git show add-a-go-cli-for-260708-edec:app/services/api/v1/project_scope.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** The configured cross-project wiki path and default fallback paths were absent, and `qmd search` returned no matching project-wiki results. The branch-local wiki maintenance/log policy still conflicts with the main-checkout wrapper instructions, so this refresh kept the main checkout's fragment-based log policy and did not edit compiled `wiki/log.md`.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T18:51:56Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout CLI/API wiki coverage after the `add-a-go-cli-for-260708-edec` review-pass commit changed wiki-facing CLI/API wording and removed wiki maintenance artifacts from its own tree.
**Pages updated:** `wiki/api-cli.md`
**Pages verified current:** `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/gaps.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:README.md`, `git show add-a-go-cli-for-260708-edec:cmd/screenote/main.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/commands_test.go`, `git show add-a-go-cli-for-260708-edec:internal/screenote/client.go`, `git show add-a-go-cli-for-260708-edec:internal/screenote/types.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** The configured cross-project wiki path and default fallback paths were absent; `qmd search` returned no matching project-wiki results. The branch tree still conflicts with current main-checkout instructions on `wiki/log.d/` fragments and compiled `wiki/log.md`, so this refresh followed the wrapper instruction to add a fragment and avoid editing compiled `wiki/log.md`.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T18:47:28Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after inspecting the `add-a-go-cli-for-260708-edec` branch wiki commit and the committed REST/Go CLI source tree it documents.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:config/routes.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, and current main-checkout wiki pages.
**Uncertainty:** The branch commit deletes `wiki/log.d/` fragments and `wiki/llm-wiki-maintenance.md` in its own tree, but current main-checkout instructions require log fragments and wrapper-owned compiled `wiki/log.md`; recorded this policy mismatch in `wiki/gaps.md`.
**Notes:** Kept edits under `/home/asterio/Dev/screenote/wiki/` only. Used `qmd search`; did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T18:23:02Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed wiki coverage after the `add-a-go-cli-for-260708-edec` branch corrected Go CLI annotation aggregation, usage exits, upload content types, compact JSON output, and CLI docs.
**Pages created:** `wiki/api-cli.md`
**Pages updated:** `wiki/index.md`, `wiki/gaps.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, committed `internal/cli/annotation.go`, `internal/cli/root.go`, `internal/cli/screenshot.go`, `internal/cli/commands_test.go`, and committed `wiki/api-cli.md`
**Notes:** Did not edit compiled `wiki/log.md`; this fragment is for the post-commit wrapper to compile. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T15:34:48Z] refresh

**Action:** Refreshed project wiki against current LLM-wiki automation and recent git history.
**Pages created:** `wiki/llm-wiki-maintenance.md`
**Pages updated:** `wiki/index.md`, `wiki/gaps.md`
**Pages unchanged after source verification:** core architecture/model/controller/MCP pages; recent commits after the prior refresh changed LLM-wiki automation and context files, not application source behavior.
**Cross-project wiki:** `.llm-wiki/config.json` still points at `/home/asterio/wikis/master/wiki`, but that path and the default fallback main wiki paths were absent on this machine during refresh.
**QMD:** Used `qmd search` only; did not run `qmd update` or `qmd embed`.
**Source:** `.llm-wiki/config.json`, `AGENTS.md`, `CLAUDE.md`, `.llm-wiki/refresh-wiki.sh`, `.llm-wiki/post-commit-refresh.sh`, `.llm-wiki/compile-log.sh`, `.claude/settings.json`, recent `git log`, source inventory under `app/`, `config/`, `db/`, `plans/`, and `todos/`.
<!-- END GENERATED WIKI LOG FRAGMENTS -->

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

## [2026-05-15] snapshot review hardening

**Action:** Clarified snapshot duplicate-commit semantics, UTC-stable labels, future timestamp validation, and model-owned project-page snapshot queries.
**Pages updated:** data-model.md, models/project.md, models/snapshot.md
**Source:** Review pass 03 fixes for the snapshot feature

## [2026-07-08] OAuth-first CLI and REST OAuth auth

**Action:** Updated API/CLI docs for OAuth-first CLI authentication and REST v1 dual bearer authentication.
**Pages updated:** wiki/api-cli.md, wiki/controllers/api-controllers.md, wiki/routes.md, wiki/log.md
**Source:** `internal/cli`, `internal/screenote`, `app/controllers/api`, `app/services/api/bearer_authenticator.rb`, controller tests

## [2026-07-09] OAuth CLI review hardening

**Action:** Hardened the OAuth CLI review findings: bounded every default HTTP path, kept saved login credentials aligned with the configured server, preserved JSON-only output when browser launch fails, masked bearer tokens from `screenote config`, and enforced owner-only permissions on existing config files.
**Pages updated:** wiki/api-cli.md, wiki/log.md
**Source:** `internal/cli`, `internal/config`, `internal/screenote`, Go regression tests

## [2026-07-09] snapshot review and current-main integration

**Action:** Re-reviewed project snapshots against current main, preserved pending-only and failed-only pages in the unfiltered project view, made empty snapshot-filter states accurate, required explicit-offset MCP timestamps, echoed snapshot linkage in capture responses, regenerated the schema so its 40-character git commit limit matches the migration, made the snapshot system test target Capybara's actual in-process server, and removed unrelated historical planning/todo artifacts from the PR.
**Pages updated:** wiki/index.md, wiki/schema-evolution.md, wiki/mcp-tools.md, wiki/models/project.md, wiki/models/snapshot.md, wiki/log.md
**Source:** `app/models/project.rb`, `app/tools/create_snapshot_tool.rb`, `app/tools/create_multi_viewport_screenshot_tool.rb`, project views, migrations, and regression tests
