---
status: pending
priority: p1
issue_id: "166"
tags: [code-review, security, multi-viewport, pr-2]
dependencies: []
---

# PR-2 upload controller must save-with-validation after `attach`

## Problem Statement
Security review of PR-1 (#28) flagged a forward-looking risk for PR-2: when the new `ScreenshotImage` upload endpoint accepts a signed-URL PUT, it must call `save!`/`update!` after `image.attach(...)` so that the `acceptable_image` validator (content-type + size) runs. If PR-2 uses direct upload + `blob.attach` without re-saving, oversize or wrong-type files persist to S3 undetected.

## Findings
- **Source**: Security Sentinel review of PR #28
- **Related**: `app/controllers/api/screenshot_uploads_controller.rb` (existing pattern — already correct for Screenshot; must mirror for ScreenshotImage)
- PR-1 inherited the existing validation pattern unchanged; the pattern is only safe when the writer re-saves after attach
- The signed-upload token invalidates on first attach, so an attacker can't re-use the token, but the corrupt blob still lands in S3

## Acceptance Criteria
- [ ] New ScreenshotImage upload endpoint calls `update!` (or `save!`) after `image.attach`, not just `attach`
- [ ] Integration test uploads a GIF via the signed URL and asserts the upload is rejected
- [ ] Integration test uploads a 25MB file and asserts the upload is rejected
