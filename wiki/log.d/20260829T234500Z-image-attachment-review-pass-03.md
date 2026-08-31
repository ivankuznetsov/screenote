## [2026-08-29] Close the last image attachment draft and replay gaps

**Action:** The commit-side slot check now counts `active_drafts` like the
reservation side, so removing an image and attaching a replacement no longer
wedges a composer at the five-file ceiling. `ClaimBatch` takes the endpoint's
`parent_type` and refuses a replayed batch whose claimed parent belongs to the
other composer, which turns a cross-composer replay into an ordinary 422
instead of a 500 or a silent no-op. A failing COMMIT now purges its staged
blob, upload streaming ends on EOF rather than on a blank chunk, and the
decoder guard shares one deadline across its keyed and global stages. Alt-text
writes answer a machine code when too long and not-found on a removal
tombstone. The composer blocks attach and remove while an interrupted upload
is settling, paints thumbnails from the picked bytes instead of re-downloading
the original, and takes its unsupported-type copy from the server constant.
Detail reads stop preloading blobs no serializer touches, the recurring
schedule is read once per environment, write-endpoint comments carry a
canonical empty `attachments` array, the draft rate limits share one explicit
scope, variant resolution and the workspace deep link each live in one place,
and the unwired draft-cleanup startup enqueue is gone.

**Pages updated:** wiki/models/image-attachment.md,
wiki/models/image-attachment-batch.md, wiki/testing-and-ci.md,
wiki/log.d/20260829T234500Z-image-attachment-review-pass-03.md

**Source:** `app/services/image_attachments/`, `app/services/image_decoding/`,
`app/services/api/v1/project_scope.rb`,
`app/services/screenote/recurring_tasks.rb`,
`app/controllers/annotations_controller.rb`,
`app/controllers/annotation_comments_controller.rb`,
`app/controllers/concerns/`, `app/controllers/image_attachment_drafts/`,
`app/mailers/notification_mailer.rb`,
`app/javascript/controllers/image_attachment_composer_controller.js`, and the
draft, submission, batch model, query budget, and browser regressions
