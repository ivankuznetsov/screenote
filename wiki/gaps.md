---
title: Gaps
type: gap
source: wiki analysis, plans/, todos/
created: 2026-04-10
updated: 2026-05-14
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
- The annotation UI (Figma-style comments, point vs region drawing, viewport switcher) is a key feature with no dedicated UI page.
- Help page redesign has landed in `app/views/static_pages/*`; no dedicated wiki page documents the public help/MCP docs UI yet.

### Configuration / Initializers
- `config/initializers/rails_simple_auth.rb` -- auth configuration details
- `config/initializers/omniauth.rb` -- OAuth provider setup
- `config/initializers/doorkeeper.rb` -- OAuth 2.1 provider config (27 OAuth todos reveal complexity)
- `config/initializers/stripe.rb` -- Stripe configuration
- MCP server configuration

### Tests
- Test structure and patterns are not documented.
- E2E test setup with Capybara + Playwright is not covered.
- **NEW:** Specific test coverage gaps identified: CreateScreenshotTool (#056), SQL injection testing (#149), OAuth test helpers (#102).

### Deployment
- Kamal configuration details beyond what's in CLAUDE.md.
- Environment variable documentation for production setup.

## Incomplete Documentation

### Admin Features
- Admin dashboard only has 3 stats. If there are admin-only features beyond the dashboard, they are not documented.

### OAuth Token Scoping
- Doorkeeper tokens can be scoped to projects (`project_id` FK on oauth_access_tokens). How this scoping works is unclear.
- **NEW:** Todo #108 proposes fundamentally rethinking this: user-scoped vs project-scoped tokens. The current architecture may change.

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
4. **NEW:** Should OAuth be user-scoped or project-scoped? (#108 -- architectural decision pending)
5. **NEW:** Are the todo frontmatter statuses authoritative, or should filenames/source evidence drive closure?

See also: [[architecture]], [[active-areas]], [[plans-and-initiatives]], [[technical-debt]]

## Environment / Automation


## Resolved Bootstrap Validation

- 2026-05-14: Managed llm-wiki config, agent context, post-commit hook, and daily systemd timer were validated for `screenote`.
- 2026-05-14: `qmd update`, `qmd embed`, and collection-scoped `qmd search` passed for `screenote`. QMD tries GPU first and falls back to CPU on this host because Vulkan headers are missing.
- 2026-05-14: `qmd query` can still be slow under the sandboxed local-model path; use `qmd search` for maintenance checks and fall back to `rg` when semantic generation is too slow.
