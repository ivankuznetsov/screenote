---
status: pending
priority: p3
issue_id: "057"
tags: [code-review, documentation, skill]
dependencies: []
---

# SKILL.md Missing Usage Instructions for resolve/create Annotation

## Problem Statement

The SKILL.md lists `create_annotation` and `resolve_annotation` in `allowed-tools` but neither workflow mode describes when or how to use them.

## Findings

- `create_annotation` is never mentioned in any workflow step
- `resolve_annotation` mentioned only as "Ask the user before resolving" with no explicit instructions
- Source: Agent-native reviewer

## Acceptance Criteria

- [ ] SKILL.md has brief guidance on when to use `create_annotation`
- [ ] `resolve_annotation` step has explicit instructions (call with annotation_id after confirmation)
