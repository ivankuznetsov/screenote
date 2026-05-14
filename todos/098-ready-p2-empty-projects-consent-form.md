---
status: ready
priority: p2
issue_id: "098"
tags: [code-review, ux, oauth, mcp]
dependencies: ["108"]
---

# Simplify Consent Form + Add create_project MCP Tool

## Problem Statement
The consent form currently has a project picker dropdown. With user-scoped authorization (#108), the project picker should be removed. Additionally, agents should be able to create projects via MCP, so a user with no projects isn't blocked.

## Findings
- `app/controllers/oauth/authorizations_controller.rb` lines 11-15: `load_projects` loads projects for dropdown
- `app/views/doorkeeper/authorizations/new.html.erb` line 38: `@projects.each` — nil guard missing, empty state broken
- Agent: silent-failure-hunter (MEDIUM #9)

## Proposed Solutions

### Option A: Remove project picker + add create_project MCP tool (Recommended)
1. Remove project picker from consent form (depends on #108 user-scoped auth)
2. Simplify consent to just show client name, scopes, approve/deny
3. Add `create_project` MCP tool so agents can create projects themselves
- **Pros**: Simpler UX, agents self-sufficient, no empty-state edge case
- **Cons**: Depends on #108
- **Effort**: Medium
- **Risk**: Low

## Technical Details
- Affected files: `app/controllers/oauth/authorizations_controller.rb`, `app/views/doorkeeper/authorizations/new.html.erb`, new `app/tools/create_project_tool.rb`

## Acceptance Criteria
- [ ] Consent form works without project picker
- [ ] Agent can create projects via MCP tool
- [ ] Nil @projects does not produce 500

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Reworked: remove project picker (depends on #108), add create_project MCP tool
