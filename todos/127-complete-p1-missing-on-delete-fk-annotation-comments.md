---
status: pending
priority: p1
issue_id: "127"
tags: [code-review, data-integrity, migration, pr-18]
dependencies: []
---

# Missing on_delete for user_id/api_key_id FKs on annotation_comments

## Problem Statement
The `create_annotation_comments` migration adds foreign keys for `user_id` and `api_key_id` without specifying `on_delete` behavior. SQLite/PostgreSQL default to RESTRICT, which means **deleting a user or revoking an API key will fail** with a foreign key violation if they have any annotation comments. This will block user deletion and API key cleanup in production.

## Findings
- `db/migrate/20260220100000_create_annotation_comments.rb`: `add_foreign_key :annotation_comments, :users` — no `on_delete` specified
- `add_foreign_key :annotation_comments, :api_keys` — no `on_delete` specified
- Both `user_id` and `api_key_id` are nullable (dual-author pattern), so `on_delete: :nullify` is the correct choice
- The `annotations` table already uses `on_delete: :nullify` for `resolved_by_user_id` and `resolved_by_api_key_id` — this is the established pattern
- Agents: data-integrity-guardian, kieran-rails-reviewer, architecture-strategist

## Proposed Solutions

### Option A: Add on_delete: :nullify (Recommended)
Create a new migration to update the foreign keys:
```ruby
class FixAnnotationCommentsForeignKeys < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :annotation_comments, :users
    remove_foreign_key :annotation_comments, :api_keys
    add_foreign_key :annotation_comments, :users, on_delete: :nullify
    add_foreign_key :annotation_comments, :api_keys, on_delete: :nullify
  end
end
```
- **Pros**: Non-breaking, preserves comment history when user/key deleted, matches existing pattern
- **Cons**: Extra migration
- **Effort**: Small
- **Risk**: Low

### Option B: Fix the original migration before merge
Amend the existing migration file since it hasn't been deployed yet.
- **Pros**: Cleaner migration history
- **Cons**: Only safe if migration hasn't run in production
- **Effort**: Small
- **Risk**: Low (pre-merge)

## Acceptance Criteria
- [ ] User deletion does not fail when user has annotation comments
- [ ] API key revocation/deletion does not fail when key has annotation comments
- [ ] Comment records are preserved with nullified author after deletion
- [ ] Test covers user deletion with existing comments

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | FK on_delete defaults to RESTRICT |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
- Existing pattern: `db/schema.rb` lines 232, 235 (annotations table on_delete: :nullify)
