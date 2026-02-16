---
status: complete
priority: p1
issue_id: "069"
tags: [code-review, rails, namespace-pollution]
dependencies: []
---

# Rake Task Helper Methods Defined at Top-Level Scope

## Problem Statement
Three helper methods (`extract_documented_tools`, `extract_actual_tools`, `compare_tools`) in `lib/tasks/validate_help_docs.rake` are defined at Ruby's top-level scope outside the Rake task block. This pollutes the `Object` namespace, making these methods available globally on every Ruby object in the application.

This is a critical issue because it can cause silent name collisions and unexpected behavior in production.

## Findings
- **Location**: `lib/tasks/validate_help_docs.rake` lines 34-120
- All three methods are `def` at indentation level 0 (top-level)
- They become private methods on `Object`, callable from anywhere
- `extract_actual_tools(*)` also has an unused splat parameter
- Consensus finding across kieran-rails-reviewer, dhh-rails-reviewer, code-simplicity-reviewer, and pattern-recognition-specialist

## Proposed Solutions

### Option 1: Move Methods Inside the Rake Task Block (Recommended)
- **Pros**: Simplest fix, methods scoped to task execution only
- **Cons**: Methods can't be reused across tasks (not needed here)
- **Effort**: Small
- **Risk**: Low

### Option 2: Wrap in a Module
- **Pros**: Clean namespace, reusable if needed
- **Cons**: More code for a single-use rake task
- **Effort**: Small
- **Risk**: Low

## Recommended Action
Move all three methods inside the `task validate: :environment do` block. Remove the unused `(*)` splat from `extract_actual_tools`. Also use `descendants` instead of `subclasses` to match the initializer pattern.

## Technical Details
- **Affected Files**: `lib/tasks/validate_help_docs.rake`
- **Related Components**: Rake tasks, help page validation
- **Database Changes**: No

## Acceptance Criteria
- [ ] Helper methods no longer pollute Object namespace
- [ ] Unused splat parameter removed from `extract_actual_tools`
- [ ] `bin/rails validate_help_docs` still passes
- [ ] Tests pass

## Work Log

### 2026-02-15 - Approved for Work
**By:** Claude Triage System
**Actions:**
- Issue approved during triage session
- Status changed from pending to ready

### 2026-02-15 - Identified in Code Review
**By:** Multi-agent review (PR #10)
**Actions:**
- Found by kieran-rails-reviewer, dhh-rails-reviewer, code-simplicity-reviewer, pattern-recognition-specialist
- All agents flagged this as critical/high priority

## Resources
- PR #10: Add MCP help page and dashboard banner
