## [2026-08-31] Share attachment hardening with API image comments

**Action:** The complete-container check introduced for browser attachment
ingest now belongs to `ImageAttachments::PrepareUpload`, the verifier shared by
browser batches and the atomic API image-comment writer. PNG, JPEG, and WebP
uploads with trailing bytes are therefore rejected consistently on both paths.
Cleanup of an unadopted staged blob also uses `ImageAttachments::PurgeBlob`, so
a provider deletion failure leaves the blob row available to reconciliation
instead of losing its durable storage key.

The browser ingest path retains the pass-4 transaction guarantees while using
the shared verifier: batch activity is renewed inside the locked ready
transition, blob ownership transfers only after commit succeeds, and a stale
failure can update only a row that is still an uploading draft.

**Pages updated:** wiki/models/image-attachment.md,
wiki/log.d/20260831T221757Z-share-image-upload-hardening.md

**Source:** `app/services/image_attachments/prepare_upload.rb`,
`app/services/image_attachments/ingest.rb`,
`test/services/image_attachments/prepare_upload_test.rb`
