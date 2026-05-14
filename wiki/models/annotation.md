---
title: Annotation
type: model
source: app/models/annotation.rb
created: 2026-04-10
updated: 2026-05-14
tags: [model, annotation, feedback, core]
---

# Annotation

TLDR: A comment pinned to a point or rectangular region of a screenshot viewport. Uses percentage-based coordinates for resolution independence. Has open/resolved status with resolve/reopen operations that create audit trail via [[annotation-comment]].

Source: `app/models/annotation.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| screenshot_id | integer | NOT NULL, FK to screenshots |
| user_id | integer | NOT NULL, FK to users (creator) |
| comment | text | NOT NULL, max 5000 chars |
| x_percent | float | NOT NULL, 0.0-100.0 |
| y_percent | float | NOT NULL, 0.0-100.0 |
| width_percent | float | Nullable (nil = point annotation) |
| height_percent | float | Nullable (nil = point annotation) |
| status | integer | Enum: open(0), resolved(1). Default: open |
| viewport | integer | Enum: desktop(0), tablet(1), mobile(2). Default: desktop |
| resolved_by_user_id | integer | FK to users (nullable) |
| resolved_by_api_key_id | integer | FK to api_keys (nullable) |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| screenshot | belongs_to | [[screenshot]] |
| user | belongs_to | [[user]] (creator) |
| resolved_by_user | belongs_to | [[user]] (optional) |
| resolved_by_api_key | belongs_to | [[api-key]] (optional) |
| annotation_comments | has_many | [[annotation-comment]] (ordered by created_at, dependent: destroy) |

## Enums

- `status`: `{ open: 0, resolved: 1 }`
- `viewport`: `{ desktop: 0, tablet: 1, mobile: 2 }`, prefix: `viewport_`

## Validations

- `comment`: presence, length max 5000
- `x_percent`, `y_percent`: presence, numericality 0.0-100.0
- `width_percent`, `height_percent`: numericality > 0.0 and <= 100.0 (allow nil)
- Custom: `region_within_bounds` -- ensures annotation region doesn't extend past image boundary

## Key Methods

- `point?` -- Returns true if width_percent is nil (point annotation vs region)
- `crop` -- Looks up the matching `ScreenshotImage` for the annotation viewport and returns a cached cropped image when that image is ready.
- `resolve!(user: nil, api_key: nil, body:)` -- Transactional: updates status to resolved, records who resolved it, creates an annotation_comment with action `:resolved`. Raises if not open.
- `reopen!(user: nil, api_key: nil, body:)` -- Transactional: updates status to open, clears resolved_by, creates an annotation_comment with action `:reopened`. Raises if not resolved.
- `as_api_json` -- Serializes for API/MCP response (id, screenshot_id, viewport, type, coordinates, comment, status, author email, comments_count)

## Notes

- Both users (web UI) and API keys (agents) can resolve/reopen annotations. The `resolved_by_user` and `resolved_by_api_key` fields track which did it.
- The `region_within_bounds` validation ensures `x + width <= 100` and `y + height <= 100`.
- Multi-viewport screenshots require explicit viewport selection for agent-created annotations; single-viewport screenshots can default to the only available viewport.

See also: [[screenshot]], [[models/screenshot-image]], [[annotation-comment]], [[services/annotation-crop-service]]
