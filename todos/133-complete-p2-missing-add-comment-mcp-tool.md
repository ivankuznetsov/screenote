---
status: pending
priority: p2
issue_id: "133"
tags: [code-review, mcp, agent-native, pr-18]
dependencies: []
---

# Missing AddAnnotationCommentTool — agents cannot add comments to threads

## Problem Statement
Users can add plain comments to annotation threads via the web UI, but there is no MCP tool for AI agents to do the same. Agents should be able to participate in annotation discussions — asking clarifying questions, providing status updates, or adding context.

## Findings
- Web UI: POST to `screenshot_annotation_annotation_comments_path` without `reopen` param creates a plain comment
- MCP: No tool exists for adding comments
- The `AnnotationComment` model supports `api_key_id` as an author
- Agents: agent-native-reviewer, architecture-strategist

## Proposed Solutions

### Option A: Create AddAnnotationCommentTool (Recommended)
```ruby
class AddAnnotationCommentTool < ApplicationTool
  tool_name "add_annotation_comment"
  description "Add a comment to an annotation thread"

  argument :annotation_id, type: "integer", required: true
  argument :body, type: "string", required: true

  def call(annotation_id:, body:)
    annotation = project.annotations.find(annotation_id)
    annotation.annotation_comments.create!(
      api_key: Current.mcp_api_key,
      body: body,
      action: :comment
    )
  end
end
```
- **Pros**: Enables agent participation in discussions
- **Cons**: New tool to maintain
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] AI agents can add comments to annotation threads via MCP
- [ ] Comments are attributed to the API key
- [ ] Comment thread is visible in web UI and via GetAnnotationTool

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | Agent-native means agents can do everything users can |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
