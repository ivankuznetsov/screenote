---
status: pending
priority: p2
issue_id: "134"
tags: [code-review, performance, conventions, pr-18]
dependencies: []
---

# sort_by(&:created_at) in view — use association default scope instead

## Problem Statement
The annotation partial sorts comments in Ruby with `annotation.annotation_comments.sort_by(&:created_at)`. This loads all comments into memory and sorts in Ruby rather than using SQL. It also puts query logic in the view layer, violating the "fat models, skinny controllers" principle.

## Findings
- `app/views/annotations/_annotation.html.erb` line 21: `.sort_by(&:created_at)`
- `GetAnnotationTool` correctly uses `.order(:created_at)` (SQL-level sort)
- Inconsistent ordering approach between view and MCP tool
- Agents: kieran-rails-reviewer, dhh-rails-reviewer, performance-oracle, pattern-recognition-specialist

## Proposed Solutions

### Option A: Add default_scope or association ordering (Recommended)
```ruby
# app/models/annotation.rb
has_many :annotation_comments, -> { order(:created_at) }, dependent: :destroy
```
Then simplify the view:
```erb
<% annotation.annotation_comments.each do |ac| %>
```
- **Pros**: Single source of truth for ordering, SQL-level sort, cleaner view
- **Cons**: Default ordering on association (some prefer explicit)
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] Comments are ordered by `created_at` via SQL, not Ruby
- [ ] View does not call `sort_by`
- [ ] Comment ordering is consistent between web UI and MCP tools

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | Prefer SQL ordering over Ruby sorting in views |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
