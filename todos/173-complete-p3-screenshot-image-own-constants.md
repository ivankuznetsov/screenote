---
status: pending
priority: p3
issue_id: "173"
tags: [code-review, multi-viewport, pr-3, cleanup]
dependencies: ["172"]
---

# Move `ALLOWED_CONTENT_TYPES` and `MAX_FILE_SIZE` ownership to ScreenshotImage

## Problem Statement
PR-1 set `ScreenshotImage::ALLOWED_CONTENT_TYPES = Screenshot::ALLOWED_CONTENT_TYPES` to share the two constants. After PR-2, ScreenshotImage is the real owner of image attachments. PR-3 (which drops Screenshot's legacy image) should flip the direction: define the constants on ScreenshotImage directly, with Screenshot referencing them only if still needed.

## Findings
- **Source**: DHH Rails Reviewer P3 on PR #29
- **Location**: `app/models/screenshot_image.rb:8-9`

## Acceptance Criteria
- [ ] `ALLOWED_CONTENT_TYPES` and `MAX_FILE_SIZE` defined on ScreenshotImage directly (or on a shared concern)
- [ ] Screenshot's references dropped when `has_one_attached :image` is removed (todo 172)
