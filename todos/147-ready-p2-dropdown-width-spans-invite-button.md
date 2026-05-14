---
status: ready
priority: p2
issue_id: "147"
tags: [code-review, css, ux]
dependencies: []
---

# Dropdown width spans over the Invite button

## Problem Statement
CSS `left: 0; right: 0` on `.autocomplete-suggestions` makes the dropdown span the full invite row width, covering the Invite button. Should be constrained to the input width.

## Findings
- **Source**: Kieran Rails Reviewer
- **Location**: `app/assets/stylesheets/application.css` lines 1108-1110

## Proposed Solutions
### Option A: Set max-width matching input (Recommended)
Add `max-width: 320px` to match `.project-members__invite-input`, or scope `position: relative` to a wrapper around just the input.
- **Effort**: Small | **Risk**: None

## Acceptance Criteria
- [ ] Dropdown width does not extend over the Invite button
