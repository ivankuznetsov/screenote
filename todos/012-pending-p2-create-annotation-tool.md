---
status: pending
priority: p2
issue_id: "012"
tags: [code-review, agent-native]
dependencies: []
---

# Add CreateAnnotationTool for Agent Feedback

## Problem Statement
Agents cannot create annotations -- they can only read and resolve them. The "agent-initiated" workflow is one-directional. Adding a CreateAnnotationTool enables bidirectional feedback and multi-agent scenarios.

## Findings
- Only 5 of 12 user-facing capabilities have MCP equivalents
- Missing: CreateAnnotation, DeleteAnnotation, DeleteScreenshot, UpdateAnnotation, ReopenAnnotation, UpdateScreenshot, GetProjectInfo
- Agents: agent-native-reviewer (Critical #1, #2)

## Proposed Solutions
Add CreateAnnotationTool accepting screenshot_id, x_percent, y_percent, optional width_percent/height_percent, and comment.
- Effort: Medium | Risk: Low

## Acceptance Criteria
- [ ] CreateAnnotationTool exists and works
- [ ] Agent-created annotations appear in web UI
- [ ] Tests verify creation and project scoping

## Work Log
- 2026-02-12: Created from code review (agent-native-reviewer)
