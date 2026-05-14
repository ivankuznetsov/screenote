---
status: ready
priority: p2
issue_id: "150"
tags: [code-review, performance, rails]
dependencies: []
---

# Three preliminary queries should be subqueries

## Problem Statement
The `exclude_emails` construction fires 2-3 separate DB queries (members pluck, invitations pluck, current user) before the main search query. These should be combined into subqueries to reduce round trips from 4 to 1.

## Findings
- **Source**: Performance Oracle, Kieran, DHH
- **Location**: `app/controllers/collaborator_suggestions_controller.rb:15-17`
- Also: `DISTINCT` adds sorting overhead; could use `WHERE users.id IN (SELECT DISTINCT user_id FROM ...)` instead

## Proposed Solutions
### Option A: Use WHERE NOT IN subqueries
Replace `pluck(:email)` with inline `SELECT` subqueries that the database can optimize.
- **Effort**: Medium | **Risk**: Low

### Option B: Extract to model scope (DHH recommendation)
`User.collaborator_suggestions_for(project:, user:, query:)` — fat model, skinny controller.
- **Effort**: Medium | **Risk**: Low

## Acceptance Criteria
- [ ] Single database round trip for the entire suggestion query
- [ ] All existing tests still pass
