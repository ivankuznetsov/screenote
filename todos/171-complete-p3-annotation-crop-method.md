---
status: pending
priority: p3
issue_id: "171"
tags: [code-review, multi-viewport, pr-3, naming]
dependencies: []
---

# Move `crop_for` from ScreenshotImage to Annotation#crop

## Problem Statement
`ScreenshotImage#crop_for(annotation)` currently wraps `AnnotationCropService.crop(self, annotation)`. The annotation owns the coordinates, viewport, and point-vs-region mode. `ScreenshotImage` shouldn't know about Annotation.

## Findings
- **Source**: Kieran Rails Reviewer P2 #4 on PR #29
- **Location**: `app/models/screenshot_image.rb` (current), `app/tools/get_annotation_tool.rb` (caller)

## Proposed Solution
```ruby
# app/models/annotation.rb
def crop(on: screenshot.image_for(viewport))
  AnnotationCropService.crop(on, self) if on
end
```
Caller: `annotation.crop` instead of `screenshot.image_for(a.viewport).crop_for(a)`.

## Acceptance Criteria
- [ ] `Annotation#crop` exists
- [ ] `ScreenshotImage#crop_for` removed
- [ ] `get_annotation_tool.rb` uses `annotation.crop`
- [ ] Tests pass
