---
status: pending
priority: p3
issue_id: "139"
tags: [code-review, quality, dry, pr-18]
dependencies: []
---

# Serialization duplication between ApplicationTool and API controller

## Problem Statement
`ApplicationTool#serialize_annotation` and `Api::V1::AnnotationsController` both serialize annotations to hashes with overlapping but not identical structures. Adding `comments_count` to both places increases the maintenance burden — changes need to be made in two places.

## Findings
- `app/tools/application_tool.rb`: `serialize_annotation` method
- `app/controllers/api/v1/annotations_controller.rb`: inline serialization in `index`/`show`
- Both now include `comments_count` but the implementations differ slightly
- Agents: pattern-recognition-specialist, code-simplicity-reviewer

## Proposed Solutions

### Option A: Extract shared serializer method on Annotation model
```ruby
# app/models/annotation.rb
def as_api_json
  { id:, x_percent:, y_percent:, ..., comments_count: annotation_comments.size }
end
```
- **Pros**: Single source of truth, DRY
- **Cons**: Model knows about serialization format
- **Effort**: Small
- **Risk**: Low

### Option B: Extract to presenter/serializer object
- **Pros**: Clean separation of concerns
- **Cons**: Additional abstraction for a simple case
- **Effort**: Medium
- **Risk**: Low

## Acceptance Criteria
- [ ] Annotation serialization logic exists in one place
- [ ] Both MCP tools and API controller use the same serialization

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | DRY serialization across API surfaces |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
