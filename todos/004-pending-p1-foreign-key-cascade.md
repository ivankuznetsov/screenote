---
status: pending
priority: p1
issue_id: "004"
tags: [code-review, data-integrity]
dependencies: []
---

# Foreign Keys on resolved_by Columns Block Deletions

## Problem Statement
The foreign keys on `annotations.resolved_by_api_key_id` and `annotations.resolved_by_user_id` have no `on_delete` clause (defaults to RESTRICT). Deleting an ApiKey that was used to resolve annotations, or deleting a User who resolved another user's annotation, will fail with a database error. This will cause production errors when cleaning up API keys or user accounts.

## Findings
- `db/migrate/20260212071517_add_foreign_key_to_annotations_resolved_by_api_key.rb`: `add_foreign_key` without `on_delete`
- `db/schema.rb`: Both resolved_by FKs lack cascade/nullify behavior
- Project model destroys screenshots before api_keys (accidentally correct order), but fragile
- Scenario: Alice creates annotation, Bob resolves it, Bob deleted -> FK violation on resolved_by_user_id
- Agents: data-integrity-guardian (HIGH #4, #5, #6)

## Proposed Solutions

### Option A: Add on_delete: :nullify migration (Recommended)
Both `resolved_by_api_key_id` and `resolved_by_user_id` are nullable columns. Add a migration that removes and re-adds the FKs with `on_delete: :nullify`.
- Pros: Preserves the annotation, just clears the resolver reference
- Cons: Requires migration
- Effort: Small
- Risk: Low

## Technical Details
- Files: New migration to alter FKs

## Acceptance Criteria
- [ ] Deleting an API key nullifies resolved_by_api_key_id on affected annotations
- [ ] Deleting a user nullifies resolved_by_user_id on affected annotations
- [ ] Project deletion succeeds cleanly regardless of resolved annotations
- [ ] Tests verify deletion cascades correctly

## Work Log
- 2026-02-12: Created from code review findings (data-integrity-guardian)
