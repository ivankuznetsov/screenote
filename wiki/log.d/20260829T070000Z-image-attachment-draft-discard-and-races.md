## [2026-08-29] Close image attachment draft races and add an explicit discard

**Action:** Added `DELETE /image-attachment-drafts/batches/:public_id` and
`ImageAttachments::DiscardBatch`, called only on an explicit Annotorious cancel
through a new `annotorious:form-cancelled` event, so the open-batch ceiling's
"finish or discard one first" copy is true; ordinary disconnect and navigation
still leave a batch for its 24 hour window. Made the ingest commit re-resolve
its own row under the batch lock, stopped a superseded attempt from un-readying
a finished row, serialized decoding per batch inside `ImageDecoding::Guard`,
and locked the account row across the per-account cap check and insert.
Reconciliation now also re-enqueues missing delivery variants. `DraftPresenter`
derives `retryable` from `Error::RETRYABLE_CODES` so a stored failure and a
live raise agree. In the composer, dragover is gated on `dataTransfer.types`
alone (a real OS drop exposes no files until the drop), item slots are reserved
synchronously, typed alt text is flushed and awaited before the claim, batch
and post requests carry the upload timeout, and a rejected post with no usable
error text still says something. CLI list rows keep `attachments` absent
instead of remarshalling an empty array. Extracted the shared blob-streaming
contract into one concern and moved the attachment CSS into a sibling
stylesheet.

**Pages updated:** wiki/routes.md, wiki/api-cli.md,
wiki/models/image-attachment-batch.md, wiki/models/image-attachment.md,
wiki/log.d/20260829T070000Z-image-attachment-draft-discard-and-races.md

**Source:** `app/services/image_attachments/`, `app/services/image_decoding/`,
`app/models/image_attachment_batch.rb`,
`app/jobs/image_attachment_orphan_reconciliation_job.rb`,
`app/controllers/concerns/blob_streaming.rb`,
`app/controllers/image_attachment_drafts/batches_controller.rb`,
`app/javascript/controllers/`, `app/assets/stylesheets/image_attachments.css`,
`internal/screenote/types.go`, and the draft, decoder, concurrency,
reconciliation, and browser regressions
