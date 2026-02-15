---
status: complete
priority: p1
issue_id: "059"
tags: [code-review, documentation, mcp, accuracy]
dependencies: []
---

# Phantom `image_path` Parameter in Help Page Documentation

## Problem Statement

The help page documents an `image_path` parameter for `create_screenshot` that does not exist in the actual `CreateScreenshotTool` class. This will cause agents to send an unsupported parameter, leading to silent failures or confusing errors.

## Findings

- Help page line 46 lists `image_path` (string) — "Path to screenshot file"
- `app/tools/create_screenshot_tool.rb` only accepts: `title` (required), `image_base64` (required), `mime_type` (optional)
- No `image_path` parameter exists anywhere in the tool code
- Found independently by architecture, agent-native, and pattern recognition reviewers
- Source: PR #10, `app/views/pages/help.html.erb:46`

## Proposed Solutions

### Option A: Remove `image_path` from documentation
- **Pros**: Immediate fix, matches actual tool interface
- **Cons**: None
- **Effort**: Small
- **Risk**: None

### Option B: Implement `image_path` in the tool
- **Pros**: Useful feature for agents with file access
- **Cons**: Requires server-side file reading, security considerations
- **Effort**: Medium
- **Risk**: Medium (path traversal concerns)

## Technical Details

- **Affected files**: `app/views/pages/help.html.erb`
- **Components**: Help page, MCP tool documentation

## Acceptance Criteria

- [ ] Help page parameters match `CreateScreenshotTool` exactly
- [ ] No phantom parameters documented
