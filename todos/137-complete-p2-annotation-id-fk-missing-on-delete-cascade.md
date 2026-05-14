---
status: pending
priority: p2
issue_id: "137"
tags: [code-review, data-integrity, migration, pr-18]
dependencies: ["127"]
---

# annotation_id FK missing on_delete: :cascade

## Problem Statement
The `annotation_id` foreign key on `annotation_comments` defaults to RESTRICT. While the model has `dependent: :destroy` on `has_many :annotation_comments`, this only works through Rails — direct database operations or edge cases (like failed callbacks) will leave orphaned records or fail. The annotation_id FK should use `on_delete: :cascade` for defense-in-depth.

## Findings
- `db/migrate/20260220100000_create_annotation_comments.rb`: `add_foreign_key :annotation_comments, :annotations` — no `on_delete`
- `annotation.rb` has `has_many :annotation_comments, dependent: :destroy`
- If annotation is deleted directly (DB admin, migration, etc.), comments become orphaned
- Agents: data-integrity-guardian, kieran-rails-reviewer

## Proposed Solutions

### Option A: Add on_delete: :cascade (Recommended)
Fix alongside todo #127 (same migration fix):
```ruby
remove_foreign_key :annotation_comments, :annotations
add_foreign_key :annotation_comments, :annotations, on_delete: :cascade
```
- **Pros**: Defense-in-depth, matches Rails dependent: :destroy semantics
- **Cons**: None
- **Effort**: Small (combine with todo #127)
- **Risk**: Low

## Acceptance Criteria
- [ ] Deleting an annotation cascades deletion to its comments at DB level
- [ ] No orphaned annotation_comments after annotation deletion

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | DB-level cascade as defense-in-depth for Rails dependent: :destroy |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
- Related: todo #127 (user_id/api_key_id FK fixes)
