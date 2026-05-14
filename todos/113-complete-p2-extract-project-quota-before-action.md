---
status: complete
priority: p2
issue_id: "113"
tags: [code-review, rails, dry, pr-11]
dependencies: []
---

# Extract Duplicated Project Limit Guard to `before_action`

## Problem Statement
The identical plan-limit check with the identical redirect and alert message is copy-pasted into both `ProjectsController#new` and `#create`. This violates DRY and the existing codebase convention of using `before_action` for guards (see `require_owner!` in `ProjectAuthorization` concern).

## Findings
- **File**: `app/controllers/projects_controller.rb`, lines 25-28 and 34-37
- Identified by: ALL 8 review agents (unanimous)
- Exact same 3-line guard with exact same message string duplicated

## Proposed Solutions

### Option A: Extract to `before_action` (Recommended)
```ruby
before_action :require_project_quota!, only: %i[new create]

private

def require_project_quota!
  return if Current.user.can_create_project?
  redirect_to subscription_path, alert: "You've reached the free plan limit of 1 project. Upgrade to Pro for unlimited projects."
end
```
- **Pros**: Idiomatic Rails, removes duplication, matches existing patterns
- **Cons**: None
- **Effort**: Small
- **Risk**: Low

## Technical Details
- Affected files: `app/controllers/projects_controller.rb`

## Acceptance Criteria
- [ ] Guard extracted to `before_action`
- [ ] Both `new` and `create` are protected
- [ ] Alert message preserved exactly
- [ ] Existing tests pass

## Work Log
- 2026-02-16: Created from PR #11 code review — unanimous finding across all agents
