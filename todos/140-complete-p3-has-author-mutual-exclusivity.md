---
status: pending
priority: p3
issue_id: "140"
tags: [code-review, data-integrity, model, pr-18]
dependencies: []
---

# has_author validation allows both user AND api_key simultaneously

## Problem Statement
The `has_author` custom validation on `AnnotationComment` only checks that at least one of `user` or `api_key` is present, but doesn't enforce mutual exclusivity. A comment could have both a user AND an api_key set, which would be semantically incorrect — a comment is authored by one entity.

## Findings
- `app/models/annotation_comment.rb`: `validate :has_author` checks `user.blank? && api_key.blank?`
- Does not validate `!(user.present? && api_key.present?)`
- In practice, the controller only sets one at a time, so this is defensive
- Agents: data-integrity-guardian, pattern-recognition-specialist

## Proposed Solutions

### Option A: Add mutual exclusivity validation
```ruby
def has_author
  if user.blank? && api_key.blank?
    errors.add(:base, "must have a user or api_key")
  elsif user.present? && api_key.present?
    errors.add(:base, "cannot have both user and api_key")
  end
end
```
- **Pros**: Data integrity, prevents impossible states
- **Cons**: Minor additional complexity
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] Cannot create a comment with both user and api_key set
- [ ] Tests cover mutual exclusivity validation

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | Validate impossible states at the model level |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
