---
status: pending
priority: p1
issue_id: "132"
tags: [code-review, mcp, agent-native, pr-18]
dependencies: []
---

# Missing ReopenAnnotationTool — agents cannot unresolve annotations

## Problem Statement
The PR adds a core workflow: unresolving annotations with a reason. Users can do this through the web UI, but there is no corresponding MCP tool for AI agents. This breaks the agent-native architecture principle: "any action a user can take, an agent can also take." The resolve→feedback→unresolve→fix cycle is the core feedback loop of Screenote.

## Findings
- Web UI: POST to `screenshot_annotation_annotation_comments_path` with `reopen: "1"` param
- MCP: `ResolveAnnotationTool` exists but no `ReopenAnnotationTool` or `UnresolveAnnotationTool`
- The `Annotation#reopen!` method already supports `api_key` pattern (though currently missing the parameter — see todo #136)
- This is the most critical agent parity gap since reopening is a key feedback loop action
- Agents: agent-native-reviewer, architecture-strategist

## Proposed Solutions

### Option A: Create ReopenAnnotationTool (Recommended)
```ruby
class ReopenAnnotationTool < ApplicationTool
  tool_name "reopen_annotation"
  description "Reopen a previously resolved annotation with an explanation"

  argument :annotation_id, type: "integer", required: true
  argument :reason, type: "string", required: true

  def call(annotation_id:, reason:)
    annotation = project.annotations.find(annotation_id)
    annotation.reopen!(api_key: Current.mcp_api_key, body: reason)
    # return updated annotation
  end
end
```
- **Pros**: Complete agent parity, enables full feedback loop
- **Cons**: New file to maintain
- **Effort**: Small (model method already exists)
- **Risk**: Low

## Acceptance Criteria
- [ ] AI agents can unresolve annotations via MCP with a reason
- [ ] The reopened comment is attributed to the API key
- [ ] The annotation status changes to open
- [ ] Tool returns updated annotation data including comment thread

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | Always ship MCP tool parity with UI features |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
- `app/tools/resolve_annotation_tool.rb` — pattern to follow
