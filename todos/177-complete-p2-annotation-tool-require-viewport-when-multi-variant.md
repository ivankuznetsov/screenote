---
status: pending
priority: p2
issue_id: "177"
tags: [code-review, mcp, ux, multi-viewport]
dependencies: []
---

# `create_annotation` tool silently defaults viewport when unspecified

## Problem Statement
`create_annotation_tool.rb` defaults `viewport: "desktop"` when the caller omits it. The existence-guard added in PR-3 raises a helpful error if the screenshot has no desktop variant — but on a screenshot that has all 3 variants, an agent that forgets to pass `viewport` silently attaches the annotation to desktop. A mobile-layout bug drawn against the mobile canvas could end up tagged as `desktop` if the agent's code path doesn't forward the param through correctly.

## Findings
- **Source**: Silent Failure Hunter review of PR #30
- **Location**: `app/tools/create_annotation_tool.rb:18` — keyword arg default

## Proposed Solution
Option A (strict): require `viewport` to be explicit when the screenshot has >1 variant. Default only when the screenshot is legacy single-viewport.

Option B (documentation-only): keep the default but add a warning log when the caller omits viewport on a multi-variant screenshot.

## Acceptance Criteria
- [ ] Agents cannot accidentally attach annotations to desktop on multi-variant screenshots
- [ ] Single-viewport screenshots keep the implicit default (backward compat)
- [ ] Tests cover both paths
