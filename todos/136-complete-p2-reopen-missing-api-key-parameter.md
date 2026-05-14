---
status: pending
priority: p2
issue_id: "136"
tags: [code-review, mcp, model, pr-18]
dependencies: ["132"]
---

# reopen! does not accept api_key parameter

## Problem Statement
`Annotation#reopen!` only accepts `user:` but not `api_key:`, while `resolve!` accepts both. This means the future `ReopenAnnotationTool` (todo #132) cannot properly attribute reopened comments to the API key. The dual-author pattern should be consistent across both methods.

## Findings
- `reopen!(user:, body:)` — missing `api_key:` kwarg
- `resolve!(user: nil, api_key: nil, body:)` — has both
- `AnnotationComment` model supports both `user_id` and `api_key_id`
- Agents: kieran-rails-reviewer, agent-native-reviewer

## Proposed Solutions

### Option A: Add api_key parameter to reopen! (Recommended)
```ruby
def reopen!(user: nil, api_key: nil, body:)
  transaction do
    update!(status: :open, resolved_by_user: nil, resolved_by_api_key: nil)
    annotation_comments.create!(user: user, api_key: api_key, body: body, action: :reopened)
  end
end
```
- **Pros**: Symmetric with resolve!, enables MCP tool
- **Cons**: None
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] `reopen!` accepts `api_key:` keyword argument
- [ ] Reopened comments can be attributed to API keys
- [ ] Existing user-based reopen tests still pass

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | Keep method signatures symmetric for paired operations |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
- Related: todo #132 (ReopenAnnotationTool)
