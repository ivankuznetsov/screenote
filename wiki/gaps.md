---
title: Gaps
type: gap
source: wiki analysis, plans/, todos/
created: 2026-04-10
updated: 2026-08-06
tags: [gaps, documentation, todo]
---

# Gaps

Areas where documentation is missing or incomplete. Updated from current source, recent git history, `plans/`, `todos/`, and the configured master wiki.

## Missing Documentation

### MCP Server / Tools
- Dedicated coverage now exists in [[mcp-tools]], but it should be expanded with exact parameter schemas from `tool.input_schema_to_json` if the API surface starts changing often.
- Source confirms `create_annotation`, `reopen_annotation`, `add_annotation_comment`, `create_project`, and invitation/membership tools now exist. Remaining missing tools are `delete_screenshot`, `delete_annotation`, plan/status or usage-limit tools, and batch feedback retrieval. See [[technical-debt]].

### Background Jobs
- `ScreenshotDimensionJob` now accepts `ScreenshotImage` and legacy `Screenshot`, but there is still no dedicated jobs wiki page covering dimension extraction, retry behavior, or digest scheduling.
- The hourly digest notification job scheduling mechanism is undocumented.
- **NEW:** Token cleanup job (#105) is proposed but not yet implemented.

### Mailers
- `ProjectInvitationMailer`, `AdminMailer`, welcome email mailer -- none are documented.
- Email templates and their dark cinematic styling (mentioned in commits) are not covered.

### Stimulus Controllers
- JavaScript controllers in `app/javascript/controllers/` are not documented.
- **NEW:** Todos reveal convention issues: imperative click listeners (#146), CDN-loaded Annotorious CSS (#016), inline style manipulation (#129). Documentation should capture the intended patterns.

### Views and Layouts
- Three layouts mentioned (`application`, `auth`, `landing`) but not documented in a dedicated page.
- The screenshot annotation and viewport interaction contract is documented in [[frontend-review-ui]]. The three layouts and the remaining non-review views still need dedicated coverage.
- The CLI-first public help and dashboard onboarding are summarized in [[active-areas]] and [[controllers/web-controllers]].

### Configuration / Initializers
- `config/initializers/rails_simple_auth.rb` -- auth configuration details
- `config/initializers/omniauth.rb` -- OAuth provider setup
- `config/initializers/doorkeeper.rb` -- OAuth 2.1 provider config (27 OAuth todos reveal complexity)
- `config/initializers/stripe.rb` -- Stripe configuration
- MCP server configuration

### Tests
- Minitest structure, focused commands, Capybara + Playwright setup, overview
  SQL budgets, and the local CI gate are documented in [[testing-and-ci]].
- **NEW:** Specific test coverage gaps identified: CreateScreenshotTool (#056), SQL injection testing (#149), OAuth test helpers (#102).

### API CLI
- [[api-cli]] now documents the Go REST CLI surface, including OAuth browser login, aggregate annotation listing, upload content-type handling, page selection, JSON output, and stable usage errors. REST parity now covers project creation and idempotent annotation resolution; remaining deferred product scope includes `annotation reopen`, snapshot-scoped feedback retrieval, daemon/watch mode, member management, and required multi-viewport upload.

### Deployment
- Kamal configuration details beyond what's in CLAUDE.md.
- Environment variable documentation for production setup.
- The unsafe rolling credential migration is resolved in source: ordinary deploys refuse the pending migration and `bin/saas-credential-cutover` now locks deployment, stops and proves predecessor processes quiesced, invokes a reviewed digest-pinned backup hook for that exact window, validates challenge/restore-point-bound evidence, migrates and verifies in one PostgreSQL transaction, and starts only the successor. The remaining production boundary is operational: the private real hook and four-role restore drill must be reviewed and retained for the cutover.

### Source release publication
- **PUBLICATION BLOCKERS:** Live GitGuardian App/incident status; GitHub main/tag rulesets and protected release-environment configuration; an immutable public CLI tag; native AMD64/ARM64 qualification runners; a versioned minimum-host profile; tracked load and public-CLI drivers; candidate-backed HTTP/HTTPS origins; and exact retained multi-platform image, scan, SBOM, qualification, provenance, and release-note evidence remain external technical gates. Pull-request source-contract jobs cannot substitute for the dedicated exact qualification run. `docs/releases/PUBLICATION_BLOCKED.md` intentionally prevents tag/image/release publication until they are complete.
- The initial predecessor-none release supports same-image local/S3 restore. The first successor release must add and qualify the exact adjacent local/S3 upgrade and rollback fixture and reconcile predecessor versus restore-image validation before it can publish.

## Incomplete Documentation

### Screenshot Storage Reconciliation
- Validated screenshot bytes are synchronously staged before attachment commit, and normal upload errors or transaction rollbacks compensate by removing the object. A hard process termination between the provider write and database commit can still leave an unreferenced object because storage and the primary database do not share a transaction. U7 should add a storage-inventory reconciler or document a dedicated staging-prefix lifecycle policy before claiming orphan-free crash recovery.

### Project Route Filtering
- Project route filters normalize and match page names in memory because stored
  names may be slash-leading paths, absolute URLs, or human labels. Thumbnail
  associations are preloaded only after filtering, but every page row is still
  materialized. If projects grow large enough for this to become measurable,
  add an indexed canonical path column and backfill it from `Page.display_path`.

### Admin Features
- Admin dashboard only has 3 stats. If there are admin-only features beyond the dashboard, they are not documented.

### Todo / Source Status Drift
- Several todos have frontmatter that appears stale compared with source. Examples: DCR/MCP rate limiting (#087/#088), Doorkeeper admin route skipping (#089), localhost-only DCR redirect URIs (#094), `CreateAnnotationTool` (#012), `ReopenAnnotationTool` (#132), and `AddAnnotationCommentTool` (#133). Do not rely on todo status alone; verify source before planning work.
- Some multi-viewport todos (#166-#178) are partly or fully represented in source but still have pending frontmatter. Close or rewrite the todos after a focused review.

## Covered Gaps (resolved since bootstrap)

The following gaps from the original bootstrap have been partially or fully addressed:

- ~~Where do MCP tool classes live?~~ Confirmed: `app/tools/` with `ApplicationTool` base class.
- Plans and todos now documented in [[plans-and-initiatives]], [[technical-debt]], and [[roadmap]].

## Questions to Resolve

1. What is the intended long-term removal plan for the legacy `Screenshot#image`, `width`, `height`, and `status` path after `ScreenshotImage` stabilizes?
2. Is there a periodic job runner for `Session.cleanup_expired!`?
3. How is the digest notification job scheduled? (Solid Queue cron? Rake task?)
4. **NEW:** Are the todo frontmatter statuses authoritative, or should filenames/source evidence drive closure?
5. The configured cross-project wiki path `/home/asterio/wikis/master/wiki` was not present during the 2026-07-08 refresh; neither were the default fallback paths `~/wikis/main/wiki/`, `../wikis/master/wiki/`, or `../wikis/main/wiki/`. `qmd search` returned no matching project-wiki results for the CLI/API refresh query. Cross-project context may be incomplete until the path is restored or config is updated.
6. The `add-a-go-cli-for-260708-edec` branch commits inspected during the 2026-07-08 worktree redirects removed `wiki/log.d/` fragments and `wiki/llm-wiki-maintenance.md` from that worktree and later rewrote compiled `wiki/log.md` back to hand-maintained style, while the main checkout refresh instructions still require new `wiki/log.d/` fragments and wrapper-owned compiled `wiki/log.md`. The residual finalizer commit on that branch also removes or simplifies source-confirmed CLI/API details from branch-local wiki pages without changing the CLI/API source files; source inspection still confirms aggregate annotation listing, shared REST pagination coercion, stable CLI usage errors, and numeric `--page` ID behavior. Treat the branch-local deletion/rewrite as unconfirmed until the main refresh automation policy is reconciled.

See also: [[architecture]], [[active-areas]], [[plans-and-initiatives]], [[technical-debt]]

## Environment / Automation

- [[llm-wiki-maintenance]] now documents current refresh scripts, QMD ownership, log fragment compilation, and worktree-safe post-commit behavior.
- `.claude/settings.json` currently has overlapping `SessionStart` hooks that both print wiki context; verify whether both are intentional before editing Claude automation.

## Resolved Bootstrap Validation

- 2026-05-14: Managed llm-wiki config, agent context, post-commit hook, and daily systemd timer were validated for `screenote`.
- 2026-05-14: `qmd update`, `qmd embed`, and collection-scoped `qmd search` passed for `screenote`. QMD tries GPU first and falls back to CPU on this host because Vulkan headers are missing.
- 2026-05-14: `qmd query` can still be slow under the sandboxed local-model path; use `qmd search` for maintenance checks and fall back to `rg` when semantic generation is too slow.
