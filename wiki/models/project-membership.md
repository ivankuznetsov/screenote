---
title: ProjectMembership
type: model
source: app/models/project_membership.rb
created: 2026-04-10
updated: 2026-04-10
tags: [model, collaboration, roles]
---

# ProjectMembership

TLDR: Join table between User and Project with a role enum (member/owner). Prevents removal of the sole owner unless the project itself is being destroyed.

Source: `app/models/project_membership.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| project_id | integer | NOT NULL, FK to projects |
| user_id | integer | NOT NULL, FK to users |
| role | integer | Enum: member(0), owner(1). Default: member |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| project | belongs_to | [[project]] |
| user | belongs_to | [[user]] |

## Enums

- `role`: `{ member: 0, owner: 1 }`

## Validations

- `user_id`: uniqueness scoped to project_id
- `role`: presence

## Callbacks

- `before_destroy :prevent_sole_owner_removal` -- Aborts destruction if this is the only owner, unless `project._destroy_in_progress` is true (project is being deleted)

## Notes

- Unique index on `(project_id, user_id)` prevents duplicate memberships.
- The owner membership is auto-created by `Project#after_create :create_owner_membership`.
- The sole-owner protection uses `throw(:abort)` to prevent accidental removal.

See also: [[project]], [[user]], [[project-invitation]]
