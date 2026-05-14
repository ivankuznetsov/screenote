---
title: Screenshot
type: model
source: app/models/screenshot.rb
created: 2026-04-10
updated: 2026-05-14
tags: [model, screenshot, image, active-storage]
---

# Screenshot

TLDR: A `Screenshot` is the logical capture/version under a page. It can have one or more [[models/screenshot-image]] viewport variants, while retaining transitional legacy image columns and attachment support for the backfill path.

Source: `app/models/screenshot.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| title | string | NOT NULL, max 255 |
| page_id | integer | NOT NULL, FK to pages |
| status | integer | Parent status synced from child ScreenshotImages. Default: pending |
| width | integer | Legacy/transitional parent width |
| height | integer | Legacy/transitional parent height |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| page | belongs_to | [[page]] |
| project | has_one through | [[project]] (via page) |
| annotations | has_many | [[annotation]] (dependent: destroy) |
| screenshot_images | has_many | [[models/screenshot-image]] (dependent: destroy) |
| image | has_one_attached | Legacy Active Storage attachment used by backfill/rollback paths |

## Enums

- `status`: `{ pending: 0, ready: 1, failed: 2 }`

## Validations

- `title`: presence, length max 255
- `width`, `height`: integer > 0 (allow nil for pending uploads)
- legacy `image`: content type must be PNG or JPEG, max 20MB when attached

## Callbacks

- Dimension extraction now belongs to [[models/screenshot-image]]. `Screenshot` status is synchronized from child images by `ScreenshotImage#sync_parent_status`.

## Key Methods

- `primary_image` -- Desktop ScreenshotImage if present, otherwise first available variant.
- `image_for(viewport)` -- ScreenshotImage for a requested viewport.
- `available_viewports` -- Ordered viewport names that have child images.
- `default_viewport` -- Desktop when present, otherwise first available viewport.
- `.create_with_image!` -- Transactionally creates a Screenshot, a desktop ScreenshotImage, attaches the blob, and saves through validators.

## Token Generation

- `Screenshot` still declares a legacy 5-minute upload token for the transitional parent attachment path.
- New signed-upload flows use [[models/screenshot-image]] tokens so each viewport upload is single-use and independent.

## Constants

- `ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg]`
- `MAX_FILE_SIZE = 20.megabytes`

## Notes

- The two-step upload flow now creates a ScreenshotImage first, returns an upload URL + token, and attaches the binary to that child image in `Api::ScreenshotUploadsController`.
- Single-image uploads still create a desktop ScreenshotImage so old callers keep working with the new reader path.

See also: [[page]], [[annotation]], [[models/screenshot-image]], [[services/annotation-crop-service]]
