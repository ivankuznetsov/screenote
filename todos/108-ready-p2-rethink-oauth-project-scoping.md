---
status: ready
priority: p2
issue_id: "108"
tags: [architecture, oauth, ux]
dependencies: []
---

# Rethink Project Scoping in OAuth — User-Scoped vs Single-Project

## Problem Statement
OAuth tokens are currently scoped to a single project (chosen during consent), mirroring the API key model. But OAuth is fundamentally different — the user authenticates as themselves. Forcing single-project selection adds friction (re-authorize per project) and doesn't match how users actually work with agents. An agent assisting a user should see everything the user can see.

## Findings
- `app/controllers/oauth/authorizations_controller.rb`: Project picker dropdown during consent
- `config/initializers/doorkeeper.rb`: `custom_access_token_attributes [:project_id]`
- `config/initializers/fast_mcp.rb`: `Project.find_by(id: access_token.project_id)` — single project lookup
- All MCP tools use `Current.mcp_project` (single project)
- Raised during triage discussion of #085

## Proposed Solutions

### Option A: User-scoped tokens (Recommended)
- Remove project picker from consent flow
- Token grants access to all user's projects
- Add `list_projects` MCP tool so agent can discover projects
- Each tool call specifies `project_id` parameter (or uses a default)
- **Pros**: Less friction, matches user mental model, single authorization
- **Cons**: Broader access if token compromised, requires tool changes
- **Effort**: Medium
- **Risk**: Medium

### Option B: Keep single-project but allow re-auth without browser
- Keep current model but allow token exchange for different project
- **Pros**: Least-privilege preserved
- **Cons**: Still friction, more complex token flow
- **Effort**: Medium
- **Risk**: Low

## Technical Details
- Affected files: `app/controllers/oauth/authorizations_controller.rb`, `config/initializers/fast_mcp.rb`, `config/initializers/doorkeeper.rb`, `app/views/doorkeeper/authorizations/new.html.erb`, all MCP tools
- Database changes: `project_id` on tokens becomes nullable or removed

## Acceptance Criteria
- [ ] Agent can access all user's projects with a single OAuth authorization
- [ ] Agent can discover available projects via MCP tool
- [ ] Each tool call specifies which project to operate on
- [ ] Existing API key auth (per-project) continues to work unchanged

## Work Log
- 2026-02-16: Created during triage — user questioned single-project scoping design
