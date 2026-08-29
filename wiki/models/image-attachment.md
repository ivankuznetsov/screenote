---
title: ImageAttachment
type: model
source: app/models/image_attachment.rb
created: 2026-08-29
updated: 2026-08-29
tags: [model, attachment, image, browser, active-storage]
---

# ImageAttachment

TLDR: One image posted with a native browser message. While it is a draft it
belongs to an [[image-attachment-batch]] and has no message parent; after the
composer posts it belongs to exactly one [[annotation]] or
[[annotation-comment]] and becomes immutable. Bytes are never public — every
read is authorized live and streamed by the application.

Source: `app/models/image_attachment.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| image_attachment_batch_id | integer | Nullable FK. Present iff the row is still a draft |
| annotation_id | integer | Nullable FK. Exactly one message parent after submission |
| annotation_comment_id | integer | Nullable FK. Exactly one message parent after submission |
| user_id | integer | NOT NULL, FK to users with `ON DELETE RESTRICT`. Immutable |
| project_id | integer | NOT NULL, FK to projects. Immutable |
| state | integer | Enum: uploading(0), ready(1), failed(2). Prefix `state` |
| client_key | string(64) | NOT NULL. Client idempotency key; unique per batch |
| alt_text | string(1000) | Nullable. Editable only while a draft |
| media_type | string(40) | `image/png`, `image/jpeg`, or `image/webp`, derived from the bytes |
| width / height | integer | Decoded dimensions |
| byte_size | bigint | Stored size, at most 20 MB |
| failure_code | string(64) | Machine code for a failed upload |

## Constraints

| Name | Meaning |
|------|---------|
| image_attachments_valid_state | state is 0, 1, or 2 |
| image_attachments_exclusive_parent | exactly one of batch / annotation / annotation_comment |
| image_attachments_submitted_ready | a row with no batch is ready and fully measured |
| image_attachments_nonnegative_bytes | byte_size is never negative |

## Limits

`MAX_FILES` 5 per message, `MAX_FILE_SIZE` 20 MB per image, `MAX_TOTAL_BYTES`
50 MB per message, `MAX_DIMENSION` and `MAX_PIXELS` shared with screenshot
policy. `ALT_TEXT_FALLBACK` is the exact string `Attached image`.

## Delivery

`has_one_attached :image` with `attachment_thumb_1x` and `attachment_thumb_2x`
variants. Variants are warmed by `ImageAttachmentThumbnailJob` only after the
batch is claimed. An authenticated GET never invokes libvips: an unwarmed
variant is simply unavailable and the gallery renders a placeholder.

Two routes read the bytes, both application-streamed with
`private, no-store` and `nosniff` and never a provider redirect:

- `GET /media/image_attachments/:id/:variant` — browser session. Drafts are
  readable only by their uploader inside a live batch; submitted rows recheck
  project membership on every request.
- `GET /api/media/image_attachments/:id?token=…` — bearer principal plus a
  five-minute `:image_attachment_media` purpose token plus live project access.
  The token alone is never authority.

## Lifecycle

Destroying an [[annotation]] or [[annotation-comment]] destroys its
attachments and purges the primary blob with every derivative.
`ImageAttachmentOrphanReconciliationJob` is the backstop in both directions: it
purges rows whose message no longer resolves after a delete that bypassed the
callbacks, and it re-enqueues `ImageAttachmentThumbnailJob` for submitted rows
whose variants were never produced, so a claim whose `perform_later` was lost
does not leave a posted gallery on its placeholder until the process restarts.
The reconciliation query selects only rows missing one of the two named
variant digests and is capped before preloading them. Re-enqueueing is
idempotent and generation aware: the job is keyed on the attachment together
with the exact blob it was asked to warm. Deleting a user whose submitted
attachments live on another member's message is rejected with a domain error
rather than orphaning the uploader identity.
