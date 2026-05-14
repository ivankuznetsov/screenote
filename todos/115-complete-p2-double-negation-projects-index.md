---
status: complete
priority: p2
issue_id: "115"
tags: [code-review, rails, views, pr-11]
dependencies: []
---

# Redundant Double-Negation in `projects/index.html.erb`

## Problem Statement
The projects index wraps `unless Current.user.pro?` around `if !Current.user.can_create_project?`. The outer `unless` is redundant because `can_create_project?` already returns true for pro users (it short-circuits with `pro? ||`). This double-negative is confusing to read.

## Findings
- **File**: `app/views/projects/index.html.erb`, lines 11-18
- Identified by: DHH, Kieran, Code Simplicity, Architecture
- `unless X` wrapping `if !Y` — two negations nesting

## Proposed Solutions

### Option A: Single check (Recommended)
```erb
<% unless Current.user.can_create_project? %>
  <div class="upgrade-banner">...</div>
<% end %>
```
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] Simplified to single conditional
- [ ] Banner still shows for free users at limit
- [ ] Banner does not show for pro users

## Work Log
- 2026-02-16: Created from PR #11 code review
