## [2026-07-13T19:00:30Z] CLI/OAuth documentation audit

**Action:** Reconciled internal command, roadmap, and initiative pages with the shipped public CLI, OAuth-only onboarding, RFC 8628 device login, and manifest snapshot workflow. Corrected the old in-repository Go install path and removed future-facing recommendations to expand MCP.
**Pages updated:** wiki/commands.md, wiki/api-cli.md, wiki/roadmap.md, wiki/plans-and-initiatives.md
**Decision:** The public `ivankuznetsov/screenote-cli` repository is the supported agent and automation surface. MCP remains server-side compatibility until its separately scoped sunset; new CLI and integration work should not extend the MCP tool surface.
**Source:** merged server PR #41, public CLI PR #5, deployed `https://screenote.ai/` and `/help`, OAuth authorization-server metadata, and the public CLI README/Go module
