---
status: pending
priority: p2
issue_id: "027"
tags: [code-review, css, architecture]
dependencies: []
---

# Split Monolithic CSS Into Separate Files

## Problem Statement
`application.css` has grown to 1,605 lines containing three entirely distinct design systems: light app styles (1-829), dark landing styles (830-1258), dark auth styles (1259-1605). These systems share zero CSS rules. Every page loads all 1,605 lines including styles it never uses. The file grew 112% in a single PR.

## Findings
- `app/assets/stylesheets/application.css`: 1,605 lines, 777 new lines added
- Landing visitors load 829 lines of app CSS they never see
- Authenticated users load 777 lines of landing/auth CSS they never use
- Agents: ALL 8 agents flagged this as P1 or P2

## Proposed Solutions

### Option A: Three separate files (Recommended)
- `application.css` — shared base + app styles (keep existing)
- `landing.css` — landing page dark theme (extract lines 830-1258)
- `auth.css` — auth shell dark theme (extract lines 1259-1605)
Each layout loads only what it needs via `stylesheet_link_tag`.
- Pros: Clean separation, smaller per-page CSS, follows Propshaft conventions
- Cons: Requires updating layout files
- Effort: Medium
- Risk: Low

## Technical Details
- **Affected files:** `app/assets/stylesheets/application.css`, new `landing.css`, new `auth.css`, layout files
- **PR:** #6

## Acceptance Criteria
- [ ] `application.css` contains only app styles (< 850 lines)
- [ ] `landing.css` contains only landing page styles
- [ ] `auth.css` contains only auth shell styles
- [ ] Each layout loads appropriate stylesheets
- [ ] All pages render correctly

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | CSS monolith is a maintenance and performance problem |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
