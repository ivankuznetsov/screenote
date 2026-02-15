---
status: pending
priority: p2
issue_id: "056"
tags: [code-review, quality, testing]
dependencies: []
---

# Missing Test Coverage for CreateScreenshotTool

## Problem Statement

Two code paths in `CreateScreenshotTool` lack test coverage:
1. File size limit branch for `image_path` (line 43-45)
2. Explicit `mime_type` override when using `image_path`

## Findings

- The file size check (`File.size > MAX_FILE_SIZE`) is untested for the path code path
- The `mime_type` parameter override with `image_path` is untested
- Source: Kieran Rails reviewer

## Proposed Solutions

### Option A: Add targeted tests
- Test file size limit: temporarily create a large fixture or mock `File.size`
- Test mime_type override: call with explicit `mime_type: "image/jpeg"` on a .png file
- **Effort**: Small

## Acceptance Criteria

- [ ] Test exercises the file-too-large error path for `image_path`
- [ ] Test verifies explicit `mime_type` overrides auto-detection from extension
