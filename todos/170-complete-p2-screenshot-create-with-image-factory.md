---
status: pending
priority: p2
issue_id: "170"
tags: [code-review, multi-viewport, pr-3, dry]
dependencies: []
---

# Extract "create Screenshot + desktop ScreenshotImage + attach + save!" factory

## Problem Statement
After PR-2, four call sites repeat the same six-line incantation:
1. `ScreenshotImage.create!(screenshot:, viewport: :desktop)`
2. `si.image.attach(...)`
3. `si.save!` (to run validators)
4. Sometimes enqueue ScreenshotDimensionJob

Locations:
- `app/tools/create_screenshot_tool.rb`
- `app/tools/create_screenshot_upload_tool.rb` (partial — only the build)
- `app/controllers/api/v1/screenshots_controller.rb`
- `app/controllers/screenshots_controller.rb`

One day someone forgets `save!` and the `acceptable_image` validators silently skip.

## Findings
- **Source**: Kieran Rails Reviewer P2, DHH Rails Reviewer P2 on PR #29
- PR-3 will add a new multi-viewport tool that needs the same pattern — good time to extract.

## Proposed Solution
Either:
- `Screenshot.create_with_image!(page:, title:, io:, filename:, content_type:, viewport: :desktop)` class method that wraps the transaction
- Or `screenshot_image.attach_image!(io:, filename:, content_type:)` on ScreenshotImage that encapsulates attach + save!

## Acceptance Criteria
- [ ] One canonical entry point for creating Screenshot + ScreenshotImage + blob
- [ ] All four existing call sites use it
- [ ] PR-3's new multi-viewport tool uses the same entry point
