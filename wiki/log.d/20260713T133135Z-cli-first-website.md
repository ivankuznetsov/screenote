## [2026-07-13T13:31:35Z] CLI-first website onboarding

**Action:** Replaced public MCP-first onboarding with verified standalone CLI installation and usage guidance across the landing page, dashboard banner, help, account surfaces, OAuth consent, legal pages, and welcome email. The help page also documents the current dashboard-only project creation and web-only annotation resolution boundaries instead of overstating CLI parity.
**Pages updated:** wiki/active-areas.md, wiki/api-cli.md, wiki/controllers/web-controllers.md, wiki/gaps.md
**Decision:** The standalone CLI is the canonical public agent interface. The existing MCP runtime and OAuth scope identifiers remain unchanged because transport retirement is a separate effort.
**Source:** `app/views/static_pages`, `app/views/projects/index.html.erb`, account and OAuth views, welcome mailer views, and the public `screenote-cli` install/command contract
