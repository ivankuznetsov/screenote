---
status: pending
priority: p2
issue_id: "138"
tags: [code-review, mcp, quality, pr-18]
dependencies: []
---

# GetAnnotationTool shows "AI Agent" without api_key name

## Problem Statement
When serializing annotation comments in `GetAnnotationTool`, the author fallback is `ac.user&.email || "AI Agent"`. This loses information — different API keys have names (e.g., "Claude MCP", "CI Bot") that should be displayed instead of a generic "AI Agent" string.

## Findings
- `app/tools/get_annotation_tool.rb`: `author: ac.user&.email || "AI Agent"`
- `ApiKey` model has a `name` attribute
- `AnnotationComment` belongs_to `:api_key, optional: true`
- The includes already loads `:user` but not `:api_key`
- Agents: agent-native-reviewer, pattern-recognition-specialist

## Proposed Solutions

### Option A: Show api_key name (Recommended)
```ruby
author: ac.user&.email || ac.api_key&.name || "Unknown"
```
Add `:api_key` to the includes chain:
```ruby
annotation.annotation_comments.includes(:user, :api_key).order(:created_at)
```
- **Pros**: Meaningful attribution, distinguishes between different agents
- **Cons**: Extra include (minor)
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] API key-authored comments show the key's name
- [ ] User-authored comments still show email
- [ ] No N+1 query for api_key loading

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | Always include meaningful attribution for all author types |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
