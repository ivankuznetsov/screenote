---
status: complete
priority: p2
issue_id: "119"
tags: [code-review, security, race-condition, pr-11]
dependencies: ["113"]
---

# TOCTOU Race on Project Creation Limit Enforcement

## Problem Statement
The project limit check (`can_create_project?`) and the project save happen without a lock. Two concurrent `POST /projects` requests from a free user with 0 projects can both pass the count check and both save, resulting in 2 projects instead of the allowed 1. The invitation acceptance path correctly uses `with_lock`, but project creation does not.

## Findings
- **File**: `app/controllers/projects_controller.rb`, lines 34-40
- **File**: `app/models/user.rb`, lines 20-22
- Identified by: Data Integrity Guardian (Low), Security Sentinel (Medium)
- Practical impact is low (tiny race window, mild consequence), but exploitable

## Proposed Solutions

### Option A: Wrap check+create in `with_lock` (Recommended)
```ruby
def create
  Current.user.with_lock do
    unless Current.user.can_create_project?
      redirect_to subscription_path, alert: "..."
      return
    end
    @project = Current.user.owned_projects.build(project_params)
    # ...
  end
end
```
- **Pros**: Eliminates race entirely
- **Cons**: Holds row lock during save
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] Concurrent project creation cannot bypass free plan limit
- [ ] Lock released promptly after save

## Work Log
- 2026-02-16: Created from PR #11 code review
