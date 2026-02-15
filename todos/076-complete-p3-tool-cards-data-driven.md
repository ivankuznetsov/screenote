---
status: complete
priority: p3
issue_id: "076"
tags: [code-review, rails, dry, help-page]
dependencies: []
---

# Tool Cards Could Be Data-Driven from ApplicationTool.subclasses

## Problem Statement
The help page hardcodes 6 tool cards in HTML. When tools are added or removed, the help page must be manually updated. The existing rake task `validate_help_docs` already detects drift, but the cards could be generated dynamically from `ApplicationTool.subclasses`.

## Findings
- **Location**: `app/views/pages/help.html.erb` (tool-grid section)
- 6 tool cards manually written in HTML
- `ApplicationTool.subclasses` already provides tool metadata (name, description, parameters)
- Rake validation task exists but is a safety net, not a fix
- Found by agent-native-reviewer, code-simplicity-reviewer

## Proposed Solutions

### Option 1: Keep Static HTML with Rake Validation (Current)
- **Pros**: Full control over presentation, no runtime dependency
- **Cons**: Manual sync required
- **Effort**: None (status quo)
- **Risk**: Low

### Option 2: Generate Tool Cards from ApplicationTool.subclasses
- **Pros**: Always in sync, DRY
- **Cons**: Less control over formatting, runtime dependency on tool classes
- **Effort**: Medium
- **Risk**: Low

## Recommended Action
Create a `_tool_card` partial driven by `ApplicationTool.descendants` metadata. Pass tool definitions from the controller. This would eliminate the validation rake task entirely.

## Technical Details
- **Affected Files**: `app/views/pages/help.html.erb`, `app/controllers/pages_controller.rb`
- **Database Changes**: No

## Acceptance Criteria
- [ ] Tool cards accurately reflect available MCP tools
- [ ] Help page renders correctly

## Work Log

### 2026-02-15 - Approved for Work
**By:** Claude Triage System
**Actions:**
- Issue approved during triage session
- Status changed from pending to ready

### 2026-02-15 - Identified in Code Review
**By:** Multi-agent review (PR #10)

## Resources
- PR #10: Add MCP help page and dashboard banner
