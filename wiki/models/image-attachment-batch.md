---
title: ImageAttachmentBatch
type: model
source: app/models/image_attachment_batch.rb
created: 2026-08-29
updated: 2026-08-29
tags: [model, attachment, draft, lifecycle]
---

# ImageAttachmentBatch

TLDR: A server-owned draft container for one mounted browser composer. Its
unguessable `public_id` is the only identifier the browser sees, and it doubles
as the one-use submission idempotency key.

Source: `app/models/image_attachment_batch.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| public_id | string(43) | NOT NULL, unique. URL-safe random, the browser-facing handle |
| user_id | integer | NOT NULL, FK to users with `ON DELETE RESTRICT` |
| project_id | integer | NOT NULL, FK to projects |
| state | integer | Enum: open(0), claimed(1). Prefix `state` |
| claimed_annotation_id | integer | Nullable FK. Set when a root annotation claimed the batch |
| claimed_annotation_comment_id | integer | Nullable FK. Set when a reply or reopen claimed it |
| last_activity_at | datetime | NOT NULL. Bumped by each successful upload |
| expires_at | datetime | NOT NULL. 24 hours after the last activity |

## Constraints

| Name | Meaning |
|------|---------|
| image_attachment_batches_valid_state | state is 0 or 1 |
| image_attachment_batches_future_expiry | expiry is after the last activity |
| image_attachment_batches_claim_state | open batches reference no parent; claimed ones reference exactly one |

## Caps

`MAX_OPEN_PER_USER` is 6 — abuse headroom for three mounted composers plus
retries, not a per-message limit. `MAX_OUTSTANDING_DRAFT_BYTES` is a
scheduler-independent backstop so a stopped cleanup supervisor cannot let one
account park unbounded bytes.

## Claim

`ImageAttachments::ClaimBatch` locks the batch, then its attachment rows by ID,
revalidates ownership, expiry, the 5-file and 50 MB limits, creates the message
inside the same transaction, moves each row onto exactly one parent FK, and
records the claimed parent. Replaying the same public ID returns the message
that was already created instead of posting twice.

## Cleanup

`ImageAttachmentDraftCleanupJob` runs every 15 minutes in production, scans a
bounded set of expired open batches, locks and rechecks each one, and destroys
it together with its blobs. `Screenote::RecurringTasks` fails readiness closed
when a supervised environment does not schedule it.
