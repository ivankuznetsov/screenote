---
status: complete
priority: p2
issue_id: "072"
tags: [code-review, performance, mcp, n-plus-1]
dependencies: []
---

# ListScreenshotsTool N+1 Queries

## Problem Statement
`ListScreenshotsTool` executes 2 COUNT queries per screenshot (`s.annotations.count` and `s.annotations.open.count`). With 50 screenshots, this means 100 extra SQL queries per MCP call. This will degrade performance as projects grow.

## Findings
- **Location**: `app/tools/list_screenshots_tool.rb` (serialization block)
- Two `COUNT(*)` queries per screenshot in the map block
- No eager loading or counter cache
- Found by performance-oracle

## Proposed Solutions

### Option 1: Use counter_cache Columns (Recommended)
- **Pros**: Zero extra queries, fast reads
- **Cons**: Requires migration to add counter columns
- **Effort**: Medium
- **Risk**: Low

### Option 2: Eager Load with .includes and .size
- **Pros**: No migration needed, reduces to 2 queries total
- **Cons**: Loads all annotation records into memory
- **Effort**: Small
- **Risk**: Low

### Option 3: Use SQL Subqueries
- **Pros**: Single query, no schema changes
- **Cons**: More complex SQL
- **Effort**: Medium
- **Risk**: Low

## Recommended Action
Use `.includes(:annotations)` and switch from `.count` to `.size` to leverage the preloaded collection. No migration needed.

## Technical Details
- **Affected Files**: `app/tools/list_screenshots_tool.rb`
- **Related Components**: MCP tools, Screenshot model, Annotation model
- **Database Changes**: Yes (if using counter_cache approach)

## Acceptance Criteria
- [ ] No N+1 queries in list_screenshots tool
- [ ] MCP E2E tests pass
- [ ] Performance improved for projects with many screenshots

## Work Log

### 2026-02-15 - Approved for Work
**By:** Claude Triage System
**Actions:**
- Issue approved during triage session
- Status changed from pending to ready

### 2026-02-15 - Identified in Code Review
**By:** Multi-agent review (PR #10)
**Actions:**
- Found by performance-oracle

## Resources
- PR #10: Add MCP help page and dashboard banner
