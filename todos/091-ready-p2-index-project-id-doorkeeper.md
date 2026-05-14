---
status: ready
priority: p2
issue_id: "091"
tags: [code-review, performance, oauth, migration]
dependencies: []
---

# Missing Indexes on project_id in Doorkeeper Tables

## Problem Statement
Both `oauth_access_grants` and `oauth_access_tokens` have `project_id` columns with foreign keys but no indexes. This impacts FK constraint checks during project deletion and any admin queries for tokens by project.

## Findings
- `db/migrate/20260216114625_create_doorkeeper_tables.rb`: No `add_index` for `project_id` on either table
- Every other table with `project_id` in the schema has an index
- Agents: data-integrity-guardian (HIGH #2), architecture-strategist

## Proposed Solutions

### Option A: Add indexes in new migration (Recommended)
```ruby
class AddProjectIdIndexesToDoorkeeperTables < ActiveRecord::Migration[8.1]
  def change
    add_index :oauth_access_grants, :project_id
    add_index :oauth_access_tokens, :project_id
  end
end
```
- Pros: Simple, follows codebase convention
- Cons: Extra migration
- Effort: Small
- Risk: Low

## Technical Details
- Affected files: New migration

## Acceptance Criteria
- [ ] Both tables have indexes on `project_id`
- [ ] `db:migrate` runs cleanly

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
