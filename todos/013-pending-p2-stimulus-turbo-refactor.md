---
status: pending
priority: p2
issue_id: "013"
tags: [code-review, rails, architecture]
dependencies: []
---

# Refactor Stimulus Controller DOM Construction to Use Turbo

## Problem Statement
The `annotorious_controller.js` `createAnnotationForm` method (60+ lines) builds a complete HTML form imperatively using `document.createElement`. This is React-style thinking. The form should be server-rendered via Turbo Frame. Also uses `document.getElementById` instead of Stimulus targets.

## Findings
- `app/javascript/controllers/annotorious_controller.js:83-142`: 60+ lines of DOM construction
- Uses `document.getElementById` instead of Stimulus targets
- CLAUDE.md: "use native Turbo logic instead of custom JavaScript wherever possible"
- Agents: dhh-rails-reviewer (Critical #2), pattern-recognition, simplicity-reviewer

## Proposed Solutions
Serve the annotation form as a server-rendered Turbo Frame partial. Use Stimulus targets for DOM references.
- Effort: Large | Risk: Medium (Annotorious integration is complex)

## Acceptance Criteria
- [ ] Annotation form is a server-rendered partial (Turbo Frame)
- [ ] Pin rendering uses Stimulus targets instead of DOM queries
- [ ] Reduced JS footprint in annotorious_controller.js

## Work Log
- 2026-02-12: Created from code review (dhh-rails-reviewer, pattern-recognition)
