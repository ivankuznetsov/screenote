---
status: complete
priority: p2
issue_id: "063"
tags: [code-review, documentation, mcp, accuracy]
dependencies: []
---

# `mime_type` Documented as "Auto-detected" but Defaults to `image/png`

## Problem Statement

The help page says `mime_type` is "auto-detected" but the `CreateScreenshotTool` code defaults to `"image/png"`. This misleads agents into thinking the tool will detect MIME type from the image data.

## Findings

- Help page states `mime_type` is "auto-detected from data"
- `CreateScreenshotTool` code: `property :mime_type, String, default: "image/png"`
- No auto-detection logic exists in the tool
- Source: Agent-native reviewer

## Proposed Solutions

### Option A: Fix documentation to say "defaults to image/png"
- **Pros**: Accurate, simple
- **Cons**: None
- **Effort**: Small
- **Risk**: None

## Technical Details

- **Affected files**: `app/views/pages/help.html.erb`
- **Components**: Help page tool reference

## Acceptance Criteria

- [ ] Documentation says "defaults to image/png" instead of "auto-detected"
