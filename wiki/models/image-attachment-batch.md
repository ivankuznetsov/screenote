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

Both caps live on the model. `ImageAttachmentBatch.open_for!` applies them to
every draft that is opened, locking the account row so the check and the insert
are one step and two composers cannot each read the same room. `Ingest`
rechecks the byte ceiling inside the commit lock so batches opened under the
cap cannot be filled past it afterwards. Expired batches that cleanup has not
yet reclaimed still hold their rows and blobs, so they keep counting toward
both caps.

## Claim

`ImageAttachments::ClaimBatch` locks the batch, then its attachment rows by ID,
revalidates ownership, expiry, the 5-file and 50 MB limits, creates the message
inside the same transaction, moves each row onto exactly one parent FK, and
records the claimed parent. Replaying the same public ID returns the message
that was already created instead of posting twice.

## Drafts

`ImageAttachments::Ingest` reserves the row for a `client_key` before it reads
a byte, so a retry reuses that slot. A key whose upload already finished is
returned exactly as it stands: replaying a lost 201 never reopens the row or
replaces its blob. `ImageAttachments::WriteAltText` and
`ImageAttachments::RemoveAttachment` both take the batch lock first, so a
description or a removal racing a claim resolves as not-found rather than
touching submitted metadata. The commit re-resolves its own row under that same
lock and answers `attachment_removed` if the row is gone, so an upload that
overlapped a removal cannot bind bytes onto a discarded slot. A failure
recorded by a superseded attempt never un-readies a row another attempt
finished.

Decoding is serialized per batch as well as globally: `ImageDecoding::Guard`
takes a per-key slot before a global one, so one batch's overlapping uploads
cannot occupy every decoder slot and answer screenshot work with
`decoder_busy`.

## Discard

`DELETE /image-attachment-drafts/batches/:public_id` throws an unclaimed batch
away, and `ImageAttachments::DiscardBatch` locks and rechecks the state first,
so a cancel racing a successful claim resolves as "already claimed" and can
never take attachments away from a posted message. Only an explicit Annotorious
cancel calls it — the composer listens for `annotorious:form-cancelled`.
Ordinary Turbo disconnect, navigation, and reconnect still leave the batch for
its 24 hour recovery window. This is what makes the open-batch ceiling's
"finish or discard one first" copy true.

## Cleanup

`ImageAttachmentDraftCleanupJob` runs every 15 minutes in production, scans a
bounded set of expired open batches, locks and rechecks each one, and destroys
it together with its blobs. `Screenote::RecurringTasks` fails readiness closed
when a supervised environment does not schedule it.
