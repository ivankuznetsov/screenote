---
status: ready
priority: p3
issue_id: "100"
tags: [code-review, simplicity, oauth]
dependencies: []
---

# Remove Dead Code in doorkeeper.rb Initializer

## Problem Statement
The Doorkeeper initializer contains three blocks that serve no purpose: `resource_owner_from_credentials` (returns nil, password grant not enabled), `skip_authorization` (always returns false, which is the default), and `allow_token_introspection false` (default behavior).

## Findings
- `config/initializers/doorkeeper.rb` lines 31, 34-36, 39-41
- Agents: dhh-rails-reviewer, code-simplicity-reviewer

## Technical Details
- Affected files: `config/initializers/doorkeeper.rb`

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
