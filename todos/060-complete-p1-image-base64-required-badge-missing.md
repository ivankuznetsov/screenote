---
status: complete
priority: p1
issue_id: "060"
tags: [code-review, documentation, mcp, accuracy]
dependencies: []
---

# `image_base64` Missing "Required" Badge in Help Page

## Problem Statement

The help page shows `image_base64` without a "required" badge, but `CreateScreenshotTool` defines it as a required parameter. Agents may omit this field thinking it's optional, causing tool call failures.

## Findings

- Help page line 45 shows `image_base64` without the `<span class="badge badge--required">required</span>` markup
- `CreateScreenshotTool` declares `image_base64` as required (same as `title`)
- `title` correctly has the required badge on line 44
- Source: PR #10, `app/views/pages/help.html.erb:45`

## Proposed Solutions

### Option A: Add required badge to `image_base64`
- **Pros**: Matches tool definition, consistent with `title` row
- **Cons**: None
- **Effort**: Small (one-line HTML change)
- **Risk**: None

## Technical Details

- **Affected files**: `app/views/pages/help.html.erb`
- **Components**: Help page tool reference

## Acceptance Criteria

- [ ] `image_base64` row has `<span class="badge badge--required">required</span>`
- [ ] Visual appearance matches `title` row's required badge
