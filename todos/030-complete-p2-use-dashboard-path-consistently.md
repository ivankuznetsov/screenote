---
status: pending
priority: p2
issue_id: "030"
tags: [code-review, rails, routing]
dependencies: []
---

# Use dashboard_path Consistently Instead of projects_path

## Problem Statement
`PagesController#landing` redirects authenticated users to `projects_path` (/projects), but `rails_simple_auth` config uses `dashboard_path` (/dashboard). Both resolve to `projects#index` today, but they generate different URLs. This inconsistency means authenticated users hit `/` → redirect to `/projects`, while after sign-in they land at `/dashboard`. Additionally, the app header logo in `application.html.erb` links to `root_path` (landing page), causing an extra redirect hop for authenticated users.

## Findings
- `app/controllers/pages_controller.rb:9`: `redirect_to projects_path if Current.user`
- `config/initializers/rails_simple_auth.rb`: `config.after_sign_in_path = :dashboard_path`
- `app/views/layouts/application.html.erb:37`: `link_to "Screenote", root_path` causes redirect hop
- Agents: architecture-strategist, kieran-rails-reviewer, dhh-rails-reviewer, agent-native-reviewer

## Proposed Solutions

### Option A: Fix both paths (Recommended)
1. Change `PagesController#landing` to use `dashboard_path` instead of `projects_path`
2. Change `application.html.erb` logo link from `root_path` to `dashboard_path`
- Pros: Consistent, no redirect hops, semantically correct
- Cons: None
- Effort: Trivial (2 one-line changes)
- Risk: None

## Technical Details
- **Affected files:** `app/controllers/pages_controller.rb`, `app/views/layouts/application.html.erb`
- **PR:** #6

## Acceptance Criteria
- [ ] `PagesController#landing` uses `dashboard_path`
- [ ] App header logo links to `dashboard_path`
- [ ] No redirect hop when authenticated user clicks logo

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | Use semantic route names consistently |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
