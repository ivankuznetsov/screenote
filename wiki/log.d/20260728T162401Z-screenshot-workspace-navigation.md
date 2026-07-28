---
title: Make page workspaces direct, resilient, and fast
type: change
date: 2026-07-28
---

- Capture the active Annotorious drawing pointer so a selection can leave an image edge and resume when it returns.
- Normalize and clamp rectangle endpoints before persisting percentage geometry, including reverse drags and zero-area cleanup.
- Clean pointer listeners and capture across cancel, disconnect, image-less workspaces, and Turbo replacement.
- Add browser regression coverage for boundary, geometry, transient cleanup, and lifecycle behavior.
- Define fixed 480x270, 960x540, and 240x160 Active Storage overview variants and warm only the ready screenshot's current primary image after dimension processing commits.
- Revalidate image/blob generation and primary identity in a concurrency-limited thumbnail job so replacement, sibling, pending, failed, and unattached records remain untouched.
- Add a batchable `screenshots:warm_thumbnails` task that is dry-run by default and reports exact candidate, skipped, processed, and failed counts.
- Make `/pages/:id` the canonical review workspace, select its newest version
  immediately, and move newest-first version history into a text-only sidebar.
- Preserve exact page version and viewport state through project/snapshot cards,
  compatibility redirects, screenshot CRUD, annotations, and annotation comments.
- Replace overview-time ad-hoc transformations with named responsive variants,
  grid-aware image markup, and fixed-batch tracked-variant preloads.
- Bound both filtered and unfiltered eight-page project views to 14 application
  SQL statements and keep project-index query growth constant as thumbnail card
  counts increase.
- Document the Minitest, Playwright, overview-performance, and full-CI contracts
  in `wiki/testing-and-ci.md`.
