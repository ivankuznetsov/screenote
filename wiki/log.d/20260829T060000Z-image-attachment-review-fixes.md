## [2026-08-29] Harden image attachment draft caps, retries, and read scopes

**Action:** Moved the per-account draft caps onto `ImageAttachmentBatch`, made
them count expired-but-unreclaimed batches, and rechecked the outstanding byte
ceiling inside the ingest commit lock. Made a replayed `client_key` return an
already-finished row untouched, measured the per-file ceiling from the uploaded
part rather than the multipart envelope, answered storage and IO failures with
the shared machine code instead of a raw 500, and moved every failure string
into one table derived from the enforced constants. Alt-text writes now take
the batch lock in the global order. Split the REST/MCP annotation scope so list
reads stay metadata-light and only detail reads preload attachment blobs.

**Pages updated:** wiki/models/image-attachment-batch.md,
wiki/log.d/20260829T060000Z-image-attachment-review-fixes.md

**Source:** `app/models/image_attachment_batch.rb`,
`app/services/image_attachments/`, `app/services/api/v1/project_scope.rb`,
`app/controllers/image_attachment_drafts/`,
`app/javascript/controllers/image_attachment_composer_controller.js`,
`internal/screenote/types.go`, and the attachment draft, concurrency, and
browser regressions
