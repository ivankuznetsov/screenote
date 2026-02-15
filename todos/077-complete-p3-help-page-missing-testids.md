---
status: complete
priority: p3
issue_id: "077"
tags: [code-review, testing, e2e, help-page]
dependencies: []
---

# Missing data-testid Attributes on Banner and Help Page Elements

## Problem Statement
The MCP banner and help page elements lack `data-testid` attributes, making it harder to write robust E2E tests. While the current test suite covers MCP tools via HTTP calls, UI elements on these pages cannot be reliably targeted.

## Findings
- **Location**: `app/views/projects/index.html.erb` (banner section)
- **Location**: `app/views/pages/help.html.erb` (tool cards, sections)
- Banner has no testid for the dismiss button or container
- Tool cards have no testids
- Help page sections have no testids
- Found by agent-native-reviewer

## Proposed Solutions

### Option 1: Add data-testid Attributes (Recommended)
- **Pros**: Enables robust E2E testing
- **Cons**: Slightly more HTML attributes
- **Effort**: Small
- **Risk**: Low

## Recommended Action
Add testids to: banner container (`mcp-banner`), dismiss button (`mcp-banner-dismiss`), CTA link (`mcp-banner-cta`), help page title (`page-title`), and tool cards (`tool-card`).

## Technical Details
- **Affected Files**: `app/views/projects/index.html.erb`, `app/views/pages/help.html.erb`
- **Database Changes**: No

## Acceptance Criteria
- [ ] Banner container, dismiss button, and CTA link have testids
- [ ] Tool cards have testids
- [ ] Help page sections have testids

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
