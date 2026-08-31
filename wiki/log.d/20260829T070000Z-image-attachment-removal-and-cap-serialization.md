## [2026-08-29] Make image attachment removal and account caps race-safe

**Action:** Draft removal now reserves the browser's client key as a bounded
tombstone, so an aborted upload cannot create a ready row after the remove
request looked for it. Claim omits and destroys tombstones, while resume hides
them. Upload commit takes the account lock before the batch lock when
rechecking the outstanding-draft byte ceiling, which serializes the cap across
different open composers. Variant reconciliation selects a bounded SQL set of
rows that are actually missing a named thumbnail digest instead of scanning
every submitted attachment in Ruby.

**Pages updated:** wiki/models/image-attachment.md,
wiki/models/image-attachment-batch.md,
wiki/log.d/20260829T070000Z-image-attachment-removal-and-cap-serialization.md

**Source:** `app/services/image_attachments/remove_attachment.rb`,
`app/services/image_attachments/ingest.rb`,
`app/services/image_attachments/claim_batch.rb`,
`app/models/image_attachment_batch.rb`,
`app/jobs/image_attachment_orphan_reconciliation_job.rb`, and the attachment
draft and concurrency regressions
