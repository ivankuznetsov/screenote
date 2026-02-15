---
status: pending
priority: p2
issue_id: "053"
tags: [code-review, architecture, mcp, agent-native]
dependencies: []
---

# N+1 Tool Calls for Annotation Feedback Retrieval

## Problem Statement

The feedback retrieval workflow requires N+1 MCP tool calls: one `list_annotations` call plus one `get_annotation` call per annotation to get cropped images. For a screenshot with 10 annotations, this is 11 sequential tool calls with significant latency and token cost.

## Findings

- `list_annotations` returns annotation metadata but no cropped images
- `get_annotation` returns one annotation with its `cropped_image_base64`
- The SKILL.md instructs: "For each annotation, call `get_annotation`"
- This is the core feedback retrieval workflow -- the primary agent operation
- Source: Agent-native reviewer

## Proposed Solutions

### Option A: Add `include_crops` parameter to `list_annotations`
- **Pros**: Single tool call, backward compatible, simple API
- **Cons**: Response can be very large with many annotations + images
- **Effort**: Small
- **Risk**: Low

### Option B: New `get_screenshot_feedback` tool
- **Pros**: Purpose-built for the use case, can include full screenshot context too
- **Cons**: Another tool to maintain
- **Effort**: Medium
- **Risk**: Low

## Technical Details

- **Affected files**: `app/tools/list_annotations_tool.rb`, `app/services/annotation_crop_service.rb`
- **Components**: MCP tools, SKILL.md

## Acceptance Criteria

- [ ] Agent can retrieve all annotations with cropped images in a single tool call
- [ ] Existing `list_annotations` behavior is unchanged without the flag
- [ ] SKILL.md updated to use the new approach
