---
title: Page
type: model
source: app/models/page.rb
created: 2026-04-10
updated: 2026-07-28
tags: [model, page, hierarchy]
---

# Page

TLDR: Groups captured versions within a project and owns their canonical review
workspace. Names are case-insensitively unique within a project.

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

- The `latest_screenshot` association uses a subquery to find the MAX(id) ready
  screenshot per page. Project overviews preload that screenshot's
  `ScreenshotImage` children, Active Storage blobs, and tracked variant records
  so thumbnail rendering does not query per card.
- `/pages/:id` opens the newest screenshot version directly. Older screenshot
  versions are selectable from the workspace sidebar via page-scoped
  `version_id`; these versions may or may not belong to a capture `Snapshot`.
- Project cards keep the exact selected screenshot id in their page-workspace
  href, including snapshot-filtered cards; they do not route through the
  compatibility screenshot URL.
- Page-card previews use the named 480x270 and 960x540 variants with responsive
  `srcset`/`sizes`. Empty pages render a placeholder without requesting image
  processing.
- The `LOWER(name)` unique index is created in migration `20260221064533`.

See also: [[project]], [[screenshot]]
