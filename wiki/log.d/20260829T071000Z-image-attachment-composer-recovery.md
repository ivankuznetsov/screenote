## [2026-08-29] Restore composer state without ghosts

**Action:** The shared attachment composer keeps its hidden batch identity
across a Stimulus disconnect, reloads the authoritative rows through the batch
resume endpoint, and rebuilds previews and listeners once. Interrupted uploads
are polled through a bounded settling window while submission stays disabled.
Draft removal is addressed by client key and remains visible when the DELETE
cannot be confirmed, so a network failure cannot hide a row that claim could
still attach. Alt-text writes are serialized per image and submission waits for
the final typed value. Permanent validation errors no longer offer Retry;
transport and server upload failures still do.

**Pages updated:** wiki/models/image-attachment-batch.md, wiki/routes.md,
wiki/log.d/20260829T071000Z-image-attachment-composer-recovery.md

**Source:**
`app/javascript/controllers/image_attachment_composer_controller.js`,
`app/controllers/image_attachment_drafts/`,
`app/services/image_attachments/draft_presenter.rb`, and the composer browser
regressions
