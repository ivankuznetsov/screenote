---
title: Snapshot processing recovery and public CLI contract gate
type: log
date: 2026-07-12
---

# Snapshot processing recovery and public CLI contract gate

**Recovery:** An unchanged manifest replay now schedules dimension processing for every attached pending ScreenshotImage. This repairs the cross-database failure window where the application attachment commits but Solid Queue enqueue fails. Concurrency is keyed by ScreenshotImage and attachment blob generation, so same-blob retries deduplicate without dropping replacement analysis; stale jobs recheck the generation before writing dimensions.

**Contract:** The public CLI owns `testdata/contracts/snapshot-digests-v1.json`. Rails loads that exact file from a separately checked-out CLI repository, executes its primitive manifest/group vectors, and submits its normalized semantic manifest through `Snapshots::PrepareUpload`; no digest literals are copied into private tests.

**CI:** Pull requests pin an immutable public CLI commit as the supported v1 candidate. A separate scheduled/manual workflow checks public CLI `main` without making a moving branch a service merge gate.

**Coverage:** A forced queue-adapter failure proves the attachment remains pending and a byte-identical manifest replay enqueues recovery. Ready and unattached images remain no-op replays.

**Source:** `app/services/snapshots/ensure_processing.rb`, `app/services/snapshots/prepare_upload.rb`, `app/jobs/screenshot_dimension_job.rb`, service/contract tests, and GitHub Actions workflows.
