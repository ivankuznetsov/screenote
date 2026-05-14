---
title: Project
type: model
source: app/models/project.rb
created: 2026-04-10
updated: 2026-05-14
tags: [model, project, core]
---

# Project

TLDR: Top-level container for pages, screenshots, and team collaboration. Belongs to a creator (User), has members via ProjectMembership, and API keys for MCP/API access.

Source: `app/models/project.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| name | string | NOT NULL, max 255 chars |
| description | text | Optional |
| user_id | integer | NOT NULL, FK to users (creator) |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| creator | belongs_to | [[user]] (foreign_key: user_id) |
| project_memberships | has_many | [[project-membership]] (dependent: destroy) |
| members | has_many through | [[user]] (via project_memberships) |
| project_invitations | has_many | [[project-invitation]] (dependent: destroy) |
| pages | has_many | [[page]] (dependent: destroy) |
| screenshots | has_many through | [[screenshot]] (via pages) |
| api_keys | has_many | [[api-key]] (dependent: destroy) |
| snapshots | has_many | [[snapshot]] (dependent: destroy) |

## Validations

- `name`: presence, length max 255

## Callbacks

- `after_create :create_owner_membership` -- Automatically creates a ProjectMembership with role `:owner` for the creator
- `before_destroy :flag_destroy_in_progress` -- Sets transient flag to allow sole-owner removal during project deletion

## Key Methods

- `member?(user)` -- Checks if user has any membership in this project
- `role_for(user)` -- Returns the user's role symbol (:member or :owner), or nil
- `owner?(user)` -- Checks if user has owner role
- `thumbnail_screenshots(limit = 4)` -- Returns up to `limit` latest ready screenshots with attached images (for project card thumbnails)

## Notes

- `_destroy_in_progress` is a transient attr_accessor used to bypass the "sole owner" check in [[project-membership]] when the entire project is being destroyed.

See also: [[user]], [[page]], [[snapshot]], [[project-membership]], [[project-invitation]], [[api-key]]
