## [2026-08-30] Add atomic CLI image comments and private thread export

**Action:** The bearer API now has a distinct `image-comments-v1` multipart
route that creates one required-body comment and one verified PNG, JPEG, or
WebP attachment as an idempotent domain operation. The successful comment row
stores the scoped receipt, handled failures purge staged provider bytes, and
the existing text-only route is never used as an image fallback. The public Go
CLI can privately spool one path or stdin image, safely retry one ambiguous
delivery with the same key, and report an unknown result without claiming a
manual rerun is deduplicated. `annotation get --attachments-dir` privately
materializes every root and reply attachment, validates same-origin
purpose-token transport and exact bytes, publishes no-overwrite local names,
strips token URLs from JSON, and composes with crop export.

The required public-CLI CI job now builds one exact CLI commit and drives body,
path-image, stdin-image, ambiguous-proxy-retry, root/reply download,
revoked/expired credential, and unsupported-server flows against a real Rails
test server. The same gate runs against disk and MinIO. PostgreSQL qualification
proves concurrent same-key requests converge on one pair, while MinIO
qualification proves API create/replay, private delivery, and compensating
provider cleanup after a post-stage database failure. The receipt migration
stays adapter-neutral and relies on quiesced release maintenance, outer
transaction rollbacks remove staged provider bytes, warming begins after the
outermost commit, all token-bearing detail responses are non-cacheable, and
test-mode self-hosted Puma does not start the production queue supervisor.
Hard process death between provider staging and database ownership, and during
multi-file local publication, remain explicit crash-recovery gaps.

**Pages updated:** wiki/api-cli.md, wiki/routes.md,
wiki/controllers/api-controllers.md, wiki/models/annotation-comment.md,
wiki/data-model.md, wiki/schema-evolution.md, wiki/testing-and-ci.md,
wiki/gaps.md, wiki/self-hosting.md,
wiki/log.d/20260830T195925Z-cli-image-comments-and-private-export.md

**Source:** `app/controllers/api/v1/image_comments_controller.rb`,
`app/services/image_attachments/create_api_comment.rb`,
`app/services/image_attachments/prepare_upload.rb`,
`app/controllers/api/image_attachment_media_controller.rb`,
`db/migrate/20260830170000_add_image_comment_idempotency_to_annotation_comments.rb`,
`script/public_cli_source_qualification`, `.github/workflows/ci.yml`, and the
public `screenote-cli` comment/image and attachment-export commands
