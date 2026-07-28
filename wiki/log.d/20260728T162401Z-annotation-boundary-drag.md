---
title: Improve screenshot review workspace behavior
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
