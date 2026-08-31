## [2026-08-31] Close the image attachment replay, lifecycle, and evidence gaps

**Action:** A claimed batch now identifies the composer that claimed it, not
just the parent class: `ClaimBatch` takes a caller-supplied matcher, so a reply
batch replayed from another thread or from the reopen disclosure is refused
instead of answering with somebody else's comment. The reopen state guard moved
inside the claim's parent builder, so a retry of a reopen whose response was
lost reaches the claimed batch and replays the comment it already created; both
create endpoints now return the parent identity, and every 422 carries the
editable form state — message body plus the root composer's coordinates and
viewport — alongside the batch and ready IDs.

Batch creation became idempotent: a composer supplies its own `client_key`, a
retry after a lost response resumes the batch that key already opened rather
than spending one of the six an account is allowed, and an expired batch holding
the key is reclaimed instead of returned. Resume refuses an expired or claimed
batch rather than restoring rows that every later request would reject.

Ingest now rejects trailing-payload polyglots by walking each accepted
container — PNG chunks to IEND, the RIFF declared length, and the JPEG marker
and entropy stream to EOI — and requiring the declared end to be the end of the
file. The ready transition renews batch activity inside the same locked
transaction, and a late failure from a superseded attempt is a conditional
update the database decides, so it can no longer revert a successful retry or a
removal tombstone. Removal tombstones are bounded to the five-file window.
Account deletion locks the user row ahead of dependent batch destruction, which
is the same order ingest takes. Blob release deletes stored bytes before the row
that names them, so a failed provider delete leaves a discoverable unattached
blob; `purge_later` has an inline fallback when the queue refuses the job, and
the reconciliation pass retries those blobs and bounds its unwarmed-variant scan
with per-row `NOT EXISTS` predicates instead of a full join and group.

Readiness stopped believing checked-in YAML on its own: a supervised environment
must also show a live Solid Queue scheduler heartbeat and the required recurring
tasks registered in the queue database. Evidence gates fail closed — a trace
that cannot start or save fails its test, and
`script/attachment_browser_evidence` refuses a non-empty output directory and
requires one trace per declared test. The PostgreSQL lifecycle workflow is a
required check on the default branch and is validated by `bin/release-validate`.
The concurrency suite proves real overlap before releasing a parked
transaction and exercises the actual 50 MB message ceiling. MCP and CLI reads
are pinned to full golden payloads rather than key allowlists, and the browser
suite posts multi-image root, reply, and reopen messages through picker, drop,
and paste, proves a failed upload blocks the post until a retry finishes it, and
covers the one-image viewer plus an explicitly dark gallery and viewer.

**Pages updated:** wiki/models/image-attachment-batch.md,
wiki/models/image-attachment.md, wiki/controllers/web-controllers.md,
wiki/testing-and-ci.md, wiki/data-model.md,
wiki/log.d/20260831T133000Z-image-attachment-review-pass-04.md

**Source:** `app/services/image_attachments/`, `app/models/image_attachment*.rb`,
`app/models/user.rb`, `app/controllers/annotation_comments_controller.rb`,
`app/controllers/concerns/image_attachment_submission.rb`,
`app/controllers/image_attachment_drafts/batches_controller.rb`,
`app/jobs/image_attachment_orphan_reconciliation_job.rb`,
`app/services/screenote/recurring_tasks.rb`,
`app/javascript/controllers/image_attachment_composer_controller.js`,
`app/assets/stylesheets/image_attachments.css`, `bin/release-validate`,
`.github/rulesets/main.json`, `script/attachment_browser_evidence`, and the
attachment lifecycle, submission, concurrency, contract, and browser suites
