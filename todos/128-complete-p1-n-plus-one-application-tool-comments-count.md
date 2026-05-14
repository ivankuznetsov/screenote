---
status: pending
priority: p1
issue_id: "128"
tags: [code-review, performance, mcp, n-plus-one, pr-18]
dependencies: []
---

# N+1 query in ApplicationTool.project_annotations for comments_count

## Problem Statement
`ApplicationTool#serialize_annotation` calls `annotation.annotation_comments.size` for every annotation, but `project_annotations` only includes `[:user, :screenshot]` — missing `:annotation_comments`. This causes an N+1 query: one extra SQL query per annotation when listing all annotations via MCP tools. With many annotations, this will degrade MCP response times significantly.

## Findings
- `app/tools/application_tool.rb`: `project_annotations` method uses `.includes(:user, :screenshot)` — missing `:annotation_comments`
- `serialize_annotation` calls `annotation.annotation_comments.size` which triggers a COUNT query per annotation
- `GetAnnotationTool` separately does `.includes(annotation_comments: :user)` for its own use — inconsistent
- Agents: kieran-rails-reviewer, performance-oracle, pattern-recognition-specialist, architecture-strategist

## Proposed Solutions

### Option A: Add :annotation_comments to includes (Recommended)
```ruby
def project_annotations
  project.annotations
         .includes(:user, :screenshot, :annotation_comments)
         .order(created_at: :desc)
end
```
- **Pros**: Simple one-line fix, eliminates all N+1 queries
- **Cons**: Loads full comments into memory (acceptable for typical volumes)
- **Effort**: Small
- **Risk**: Low

### Option B: Use counter_cache
Add `counter_cache: true` to the `belongs_to :annotation` in AnnotationComment.
- **Pros**: Zero extra queries, cached count
- **Cons**: Requires migration to add column, more complexity
- **Effort**: Medium
- **Risk**: Low

## Acceptance Criteria
- [ ] Listing annotations via MCP does not trigger N+1 queries for comments_count
- [ ] `bullet` gem (or log inspection) shows no extra queries in annotation listing

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | Always update includes when adding associations to serialization |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
- `app/tools/application_tool.rb`
