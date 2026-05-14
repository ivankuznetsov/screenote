---
status: complete
priority: p3
issue_id: "153"
tags: [code-review, agent-native, mcp]
dependencies: []
---

# No MCP tools for invitation/membership domain (pre-existing gap)

## Problem Statement
The entire invitation/membership workflow (invite, cancel invite, list members, remove member) has zero MCP tool coverage. An agent cannot help manage team collaboration. This is a pre-existing gap, not introduced by this PR.

## Findings
- **Source**: Agent-Native Reviewer
- 0/5 collaboration capabilities are agent-accessible
- 13/13 existing tools in other domains are properly registered

## Acceptance Criteria
- [x] InviteCollaboratorTool created (highest priority)
- [x] ListProjectMembersTool created
- [x] CancelInvitationTool and RemoveProjectMemberTool created
