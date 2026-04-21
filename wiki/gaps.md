---
title: Gaps
type: gap
source: wiki analysis, plans/, todos/
created: 2026-04-10
updated: 2026-04-11
tags: [gaps, documentation, todo]
---

# Gaps

Areas where documentation is missing or incomplete. Updated with cross-references from plans/ and todos/ ingestion.

## Missing Documentation

### MCP Server / Tools
- MCP tool classes live in `app/tools/` (confirmed from plans). A wiki page documenting each tool, its parameters, and auth behavior is needed.
- The MCP transport configuration and endpoints need a dedicated wiki page.
- **NEW:** 7 missing MCP tools identified in todos (#012, #054, #055, #098, #120, #132, #133, #153) -- the gap is not just documentation but actual missing functionality. See [[technical-debt]].

### Background Jobs
- `ScreenshotDimensionJob` behavior and failure handling are not documented.
- The hourly digest notification job scheduling mechanism is undocumented.
- **NEW:** Token cleanup job (#105) is proposed but not yet implemented.

### Mailers
- `ProjectInvitationMailer`, `AdminMailer`, welcome email mailer -- none are documented.
- Email templates and their dark cinematic styling (mentioned in commits) are not covered.

### Stimulus Controllers
- JavaScript controllers in `app/javascript/controllers/` are not documented.
- **NEW:** Todos reveal convention issues: imperative click listeners (#146), CDN-loaded Annotorious CSS (#016), inline style manipulation (#129). Documentation should capture the intended patterns.

### Views and Layouts
- Three layouts mentioned (`app`, `auth`, `landing`) but not documented.
- The annotation UI (Figma-style comments, point vs region drawing) is a key feature with no documentation.
- **NEW:** Help page redesign plan will split help into partials and add guest navigation. Documentation should be updated after implementation.

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

### Page/Version Hierarchy (NEW)
- The Page model exists in wiki ([[models/page]]) but the full hierarchy plan (plans/project-page-version-hierarchy.md) has not been implemented yet. Wiki should be updated after implementation to reflect the new Project -> Page -> Version structure.

## Covered Gaps (resolved since bootstrap)

The following gaps from the original bootstrap have been partially or fully addressed:

- ~~Where do MCP tool classes live?~~ Confirmed: `app/tools/` with `ApplicationTool` base class.
- Plans and todos now documented in [[plans-and-initiatives]], [[technical-debt]], and [[roadmap]].

## Questions to Resolve

1. What does `ScreenshotDimensionJob` do on failure? Does it set screenshot status to `failed`?
2. Is there a periodic job runner for `Session.cleanup_expired!`?
3. How is the digest notification job scheduled? (Solid Queue cron? Rake task?)
4. **NEW:** Should OAuth be user-scoped or project-scoped? (#108 -- architectural decision pending)
5. **NEW:** What is the migration strategy for Page/Version hierarchy with existing production data?

See also: [[architecture]], [[active-areas]], [[plans-and-initiatives]], [[technical-debt]]
