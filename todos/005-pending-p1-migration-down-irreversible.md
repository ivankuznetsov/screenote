---
status: pending
priority: p1
issue_id: "005"
tags: [code-review, data-integrity, migration]
dependencies: []
---

# Migration Down Method Should Raise IrreversibleMigration

## Problem Statement
The `add_token_digest_to_api_keys` migration's `down` method re-adds the `token` column but leaves it NULL for all rows. SHA-256 hashes cannot be reversed, so rolling back silently produces a broken state where every API key is unusable. The `down` method should fail loudly instead of silently corrupting data.

## Findings
- `db/migrate/20260212151018_add_token_digest_to_api_keys.rb:23-29`: Down re-adds token column as nullable, doesn't populate
- Original create_api_keys had `null: false` on token, down doesn't match
- Also recommended: squash the two api_keys migrations since neither has been deployed
- Agents: data-integrity-guardian (CRITICAL #2), data-migration-expert (Finding #2)

## Proposed Solutions

### Option A: Squash migrations (Recommended - since neither deployed yet)
Combine `create_api_keys` and `add_token_digest_to_api_keys` into a single migration that creates the table with `token_digest` and `token_prefix` from the start. No backfill needed.
- Pros: Clean history, no dead code, no irreversible concern
- Cons: Requires regenerating schema
- Effort: Small
- Risk: Low

### Option B: Change down to raise IrreversibleMigration
Replace the down method body with `raise ActiveRecord::IrreversibleMigration`.
- Pros: Minimal change, loud failure
- Cons: Leaves dead code in migration history
- Effort: Small
- Risk: Low

## Technical Details
- Files: `db/migrate/20260212071431_create_api_keys.rb`, `db/migrate/20260212151018_add_token_digest_to_api_keys.rb`

## Acceptance Criteria
- [ ] Either: single migration creates api_keys with token_digest from start
- [ ] Or: down method raises IrreversibleMigration
- [ ] db:migrate from scratch works cleanly
- [ ] Tests pass

## Work Log
- 2026-02-12: Created from code review findings (data-integrity-guardian, data-migration-expert)
