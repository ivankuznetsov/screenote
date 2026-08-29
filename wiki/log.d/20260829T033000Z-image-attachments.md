## [2026-08-29] Image attachments for native browser messages

**Action:** Added images to the annotation root composer and the reply and
reopen composers. Uploads stream into a server-owned draft batch whose
unguessable public ID is also the one-use submission key; posting binds every
ready row to exactly one Annotation or AnnotationComment inside the same
transaction that creates the message. Streaming, byte-derived type detection,
and a full decode through the global two-slot guard run with no row lock held,
and only the aggregate recheck and the state transition are serialized. A
rejected post answers 422 with the batch and its ready row IDs so the mounted
composer keeps its text and images. Bytes are delivered by the application
after live authorization on two routes — a browser session route and a bearer
route requiring a five-minute purpose token in addition to the credential —
and Active Storage's public routes stay disabled. REST, MCP, and CLI detail
reads gained an always-present `attachments` array on the root annotation and
on every comment without renaming, dropping, or nesting any shipped key.
Expiry cleanup and orphan reconciliation are scheduled, and readiness fails
closed when a supervised environment does not register them.

**Pages updated:** wiki/models/image-attachment.md,
wiki/models/image-attachment-batch.md, wiki/models/annotation.md,
wiki/models/annotation-comment.md, wiki/data-model.md, wiki/routes.md,
wiki/mcp-tools.md, wiki/api-cli.md, wiki/testing-and-ci.md, wiki/gaps.md,
wiki/index.md, wiki/log.d/20260829T033000Z-image-attachments.md

**Source:** migration `20260829120000`, `app/models/image_attachment*.rb`,
`app/services/image_attachments/`, `app/controllers/image_attachment_drafts/`,
`app/controllers/image_attachment_media_controller.rb`,
`app/controllers/api/image_attachment_media_controller.rb`,
`app/javascript/controllers/image_attachment_*_controller.js`,
`app/jobs/image_attachment_*_job.rb`, `internal/screenote/types.go`, and the
focused model, request, job, contract, concurrency, and browser regressions
