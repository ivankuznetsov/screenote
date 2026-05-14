---
status: pending
priority: p1
issue_id: "131"
tags: [code-review, security, controller, pr-18]
dependencies: []
---

# annotation_params still permits :status — bypasses comment thread mechanism

## Problem Statement
`AnnotationsController#annotation_params` still permits `:status`, allowing a PATCH request with `annotation[status]=open` to reopen an annotation without going through the comment thread mechanism. This bypasses the `reopen!` workflow entirely — no "reopened" comment is created, no audit trail. The whole point of the comment thread feature is to require an explanation when unresolving.

## Findings
- `app/controllers/annotations_controller.rb`: `params.require(:annotation).permit(:comment, :status, :x_percent, ...)`
- The `update` action calls `@annotation.resolve!` when `resolving?` is true, but a `status: "open"` would just use `@annotation.update!(annotation_params)` directly
- This creates a backdoor that circumvents the new comment thread workflow
- Agents: kieran-rails-reviewer, dhh-rails-reviewer, architecture-strategist

## Proposed Solutions

### Option A: Remove :status from annotation_params (Recommended)
```ruby
def annotation_params
  params.require(:annotation).permit(:comment, :x_percent, :y_percent, :width_percent, :height_percent)
end
```
Handle resolve via a dedicated route or keep the existing `resolving?` check but remove `:status` from the general params.
- **Pros**: Enforces comment thread for all status changes, clean separation
- **Cons**: Need separate mechanism for resolve (already exists via `resolving?` check)
- **Effort**: Small
- **Risk**: Low — resolve is already handled separately

### Option B: Filter :status in update action
Only allow `resolved` via the existing `resolving?` path, reject `open`:
```ruby
def update
  if resolving?
    @annotation.resolve!(user: Current.user)
  else
    @annotation.update!(annotation_params.except(:status))
  end
end
```
- **Pros**: Backward compatible
- **Cons**: More complex logic in controller
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] PATCH with `annotation[status]=open` does NOT reopen the annotation
- [ ] Reopening only works through the annotation_comments endpoint with reopen flag
- [ ] Existing resolve functionality still works
- [ ] Test covers attempted status bypass

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | When adding a new workflow, close the old backdoor |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
- `app/controllers/annotations_controller.rb`
