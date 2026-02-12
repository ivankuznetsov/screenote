---
status: pending
priority: p3
issue_id: "019"
tags: [code-review, architecture]
dependencies: []
---

# Extract Annotation Serialization Helper to DRY Tools

## Problem Statement
GetAnnotationTool and ListAnnotationsTool have nearly identical annotation-to-hash serialization code. Also, the project_annotations scoping query is duplicated in 3 tools.

## Proposed Solutions
Extract `annotation_to_hash(annotation)` and `project_annotations` into ApplicationTool.
- Effort: Small | Risk: Low

## Work Log
- 2026-02-12: Created from code review (pattern-recognition, simplicity-reviewer)
