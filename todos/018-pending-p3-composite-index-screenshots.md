---
status: pending
priority: p3
issue_id: "018"
tags: [code-review, performance]
dependencies: []
---

# Add Composite Index on screenshots (project_id, created_at)

## Problem Statement
Every query loading screenshots for a project orders by `created_at: :desc`, but only a single-column index on `project_id` exists. PostgreSQL must sort all matching rows.

## Proposed Solutions
`add_index :screenshots, [:project_id, :created_at]`
- Effort: Small | Risk: Low

## Work Log
- 2026-02-12: Created from code review (performance-oracle OPT-9)
