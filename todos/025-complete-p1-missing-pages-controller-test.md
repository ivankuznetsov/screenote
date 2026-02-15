---
status: pending
priority: p1
issue_id: "025"
tags: [code-review, testing]
dependencies: []
---

# Missing Controller Test for PagesController

## Problem Statement
`PagesController` has branching logic (`redirect_to projects_path if Current.user`) but no test coverage. Every other controller in the project has tests. This controller is the first thing users see (root route) and has authentication-dependent behavior that must be verified.

## Findings
- `app/controllers/pages_controller.rb`: New controller with conditional redirect logic, untested
- `test/controllers/` has tests for: annotations, api_keys, projects, screenshots — but not pages
- Agents: kieran-rails-reviewer (P1), architecture-strategist (P1)

## Proposed Solutions

### Option A: Add controller test (Recommended)
Create `test/controllers/pages_controller_test.rb` with at minimum:
1. Unauthenticated user hits root → gets 200 with landing layout
2. Authenticated user hits root → redirected to dashboard
- Pros: Complete coverage, follows project conventions
- Cons: None
- Effort: Small
- Risk: Low

## Technical Details
- **Affected files:** `test/controllers/pages_controller_test.rb` (new)
- **PR:** #6

## Acceptance Criteria
- [ ] Test file exists at `test/controllers/pages_controller_test.rb`
- [ ] Test: unauthenticated user gets 200 on root
- [ ] Test: authenticated user is redirected to dashboard from root
- [ ] All tests pass

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | New controllers with branching logic need tests |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
