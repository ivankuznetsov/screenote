---
title: Page
type: model
source: app/models/page.rb
created: 2026-04-10
updated: 2026-04-10
tags: [model, page, hierarchy]
---

# Page

TLDR: Groups screenshots within a project. Added in Phase 4 (commit `dea90b0`) to organize screenshots by logical grouping (e.g., URL, feature area). Names are case-insensitively unique within a project.

Source: `app/models/page.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| name | string | NOT NULL, max 255, unique per project (case-insensitive) |
| project_id | integer | NOT NULL, FK to projects |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| project | belongs_to | [[project]] |
| screenshots | has_many | [[screenshot]] (dependent: destroy) |
| latest_screenshot | has_one | [[screenshot]] (latest ready screenshot by ID) |

## Validations

- `name`: presence, length max 255
- `name`: uniqueness scoped to project_id (case-insensitive)

## Scopes

- `ordered` -- `order(:created_at)`

## Key Methods

- `self.find_or_create_by_name!(project, name)` -- Case-insensitive find-or-create with race condition handling. Uses `LOWER()` to match the database index. Retries on `RecordNotUnique` (concurrent creation). Used by the API when agents upload screenshots.

## Notes

- The `latest_screenshot` association uses a subquery to find the MAX(id) ready screenshot per page. This powers thumbnail previews in the project view.
- The `LOWER(name)` unique index is created in migration `20260221064533`.

See also: [[project]], [[screenshot]]
