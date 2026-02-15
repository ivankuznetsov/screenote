---
status: complete
priority: p3
issue_id: "068"
tags: [code-review, architecture, mcp, documentation]
dependencies: []
---

# Consider Auto-Generating Tool Reference from Tool Classes

## Problem Statement

The help page manually documents MCP tool parameters, which can drift from actual tool definitions (as seen with the `image_path` phantom parameter). Generating the reference from `ApplicationTool` subclasses would prevent this.

## Findings

- PR #10 already has 3 documentation inaccuracies vs actual tool code
- Tool classes define parameters with types, requirements, and defaults
- Manual documentation is error-prone and requires updates in two places
- Source: Agent-native and architecture reviewers

## Proposed Solutions

### Option A: Helper method that reads tool metadata
- **Pros**: Always accurate, single source of truth
- **Cons**: More complex view logic, tool classes need to expose metadata
- **Effort**: Medium
- **Risk**: Low

### Option B: Rake task to validate docs match tool definitions
- **Pros**: Catches drift in CI, keeps human-readable docs
- **Cons**: Still manual docs, just validated
- **Effort**: Small
- **Risk**: Low

## Technical Details

- **Affected files**: `app/helpers/`, `app/views/pages/help.html.erb`, `app/tools/`
- **Components**: Help page, MCP tools, asset pipeline

## Acceptance Criteria

- [ ] Tool parameters in help page cannot drift from actual tool definitions
