---
status: pending
priority: p3
issue_id: "058"
tags: [code-review, agent-native, mcp]
dependencies: []
---

# `create_screenshot` Response Missing Status Field

## Problem Statement

The `create_screenshot` tool returns `{ screenshot_id, annotate_url }` but not the screenshot's processing `status`. After upload, the screenshot goes through async dimension extraction (`ScreenshotDimensionJob`). The agent has no way to know it should wait for `ready` status.

## Findings

- `list_screenshots` returns status, but `create_screenshot` does not
- Cropped images in `get_annotation` only work when screenshot is `ready`
- Source: Agent-native reviewer

## Acceptance Criteria

- [ ] `create_screenshot` response includes `status` field
- [ ] Consider adding a note that the screenshot may take a moment to become `ready`
