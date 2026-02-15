---
status: complete
priority: p2
issue_id: "075"
tags: [code-review, documentation, mcp]
dependencies: []
---

# auth_token: "ignored" Is Confusing Magic Value

## Problem Statement
The string `"ignored"` is passed as `auth_token:` in two places in `fast_mcp.rb`. Without context, it looks like a placeholder or oversight. A comment explaining why this value exists (FastMcp requires a non-nil token but our custom transport validates against the database instead) would prevent confusion.

## Findings
- **Location**: `config/initializers/fast_mcp.rb` lines 67, 88
- `auth_token: "ignored"` appears twice
- FastMcp gem requires this parameter to be non-blank to enable auth
- Our `ProjectAuthTransport` overrides `valid_token?` to check the database
- Found by dhh-rails-reviewer, code-simplicity-reviewer

## Proposed Solutions

### Option 1: Add Inline Comment (Recommended)
- **Pros**: Clear intent, minimal change
- **Cons**: None
- **Effort**: Small
- **Risk**: Low

### Option 2: Extract to Named Constant
- **Pros**: Self-documenting, DRY
- **Cons**: Over-engineering for a string used twice
- **Effort**: Small
- **Risk**: Low

## Recommended Action
Replace `"ignored"` with `SecureRandom.hex(32)` and add a comment explaining that FastMcp requires a non-nil token to enable auth mode, but `ProjectAuthTransport` overrides `valid_token?` to validate against the database.

## Technical Details
- **Affected Files**: `config/initializers/fast_mcp.rb`
- **Database Changes**: No

## Acceptance Criteria
- [ ] Purpose of "ignored" auth_token is documented
- [ ] No functional changes

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
