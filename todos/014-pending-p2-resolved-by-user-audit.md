---
status: pending
priority: p2
issue_id: "014"
tags: [code-review, data-integrity]
dependencies: ["004"]
---

# Set resolved_by_user When Resolving via Web UI

## Problem Statement
When a user resolves an annotation through the web UI, `resolved_by_user_id` remains NULL. Only the MCP path sets `resolved_by_api_key`. This breaks the audit trail.

## Findings
- `app/controllers/annotations_controller.rb:47`: permits `:status` in params but doesn't set resolved_by_user
- `app/tools/resolve_annotation_tool.rb`: correctly sets resolved_by_api_key
- Agents: architecture-strategist, data-integrity-guardian, pattern-recognition

## Proposed Solutions
In the controller update action, set resolved_by_user when status changes to resolved:
```ruby
if @annotation.update(annotation_params)
  @annotation.update(resolved_by_user: Current.user) if @annotation.resolved?
end
```
- Effort: Small | Risk: Low

## Acceptance Criteria
- [ ] Web-resolved annotations have resolved_by_user_id set
- [ ] Test verifies audit trail on web resolve

## Work Log
- 2026-02-12: Created from code review (3 agents flagged this)
