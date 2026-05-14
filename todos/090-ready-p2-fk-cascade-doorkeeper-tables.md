---
status: ready
priority: p2
issue_id: "090"
tags: [code-review, data-integrity, oauth, migration]
dependencies: []
---

# Missing on_delete Strategies on Doorkeeper Foreign Keys

## Problem Statement
All 6 foreign keys in the Doorkeeper migration lack `on_delete` behavior. The default is `RESTRICT`, meaning deleting a project or user that has OAuth tokens/grants will raise `ActiveRecord::InvalidForeignKey`, blocking the deletion. This is a GDPR right-to-deletion compliance concern.

## Findings
- `db/migrate/20260216114625_create_doorkeeper_tables.rb` lines 33-35 and 52-54
- Codebase already fixed this pattern before: `db/migrate/20260212153509_fix_resolved_by_foreign_key_cascade.rb`
- Agent: data-integrity-guardian (CRITICAL #1)

## Proposed Solutions

### Option A: New migration with appropriate on_delete (Recommended)
Create `db/migrate/XXX_add_cascade_to_doorkeeper_foreign_keys.rb`:
```ruby
class AddCascateToDoorkeeperForeignKeys < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :oauth_access_grants, :oauth_applications, column: :application_id
    remove_foreign_key :oauth_access_grants, :projects, column: :project_id
    remove_foreign_key :oauth_access_grants, :users, column: :resource_owner_id
    remove_foreign_key :oauth_access_tokens, :oauth_applications, column: :application_id
    remove_foreign_key :oauth_access_tokens, :projects, column: :project_id
    remove_foreign_key :oauth_access_tokens, :users, column: :resource_owner_id

    add_foreign_key :oauth_access_grants, :oauth_applications, column: :application_id, on_delete: :cascade
    add_foreign_key :oauth_access_grants, :projects, column: :project_id, on_delete: :nullify
    add_foreign_key :oauth_access_grants, :users, column: :resource_owner_id, on_delete: :cascade
    add_foreign_key :oauth_access_tokens, :oauth_applications, column: :application_id, on_delete: :cascade
    add_foreign_key :oauth_access_tokens, :projects, column: :project_id, on_delete: :nullify
    add_foreign_key :oauth_access_tokens, :users, column: :resource_owner_id, on_delete: :cascade
  end
end
```
- Pros: Fixes the issue, follows existing codebase pattern
- Cons: Extra migration file
- Effort: Small
- Risk: Low

## Technical Details
- Affected files: New migration

## Acceptance Criteria
- [ ] Deleting a project does not raise FK violation
- [ ] Deleting a user cascades to their grants and tokens
- [ ] Deleting an application cascades to its grants and tokens

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
