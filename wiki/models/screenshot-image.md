---
title: ScreenshotImage
type: model
source: app/models/screenshot_image.rb
created: 2026-05-14
updated: 2026-07-10
tags: [model, screenshot, image, viewport, active-storage]
---

# ScreenshotImage

TLDR: `ScreenshotImage` is the per-viewport image variant for a [[screenshot]]. It owns the Active Storage blob, dimensions, status, upload token, and backfill/rollback helpers for the multi-viewport migration.

Source: `app/models/screenshot_image.rb`, `db/migrate/20260421110931_create_screenshot_images.rb`, `db/migrate/20260421114232_backfill_screenshot_images.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| screenshot_id | integer | NOT NULL, FK to screenshots |
| viewport | integer | Enum: desktop(0), tablet(1), mobile(2). Unique per screenshot |
| status | integer | Enum: pending(0), ready(1), failed(2). Default: pending |
| width | integer | Pixel width from Active Storage analysis |
| height | integer | Pixel height from Active Storage analysis |
| content_sha256 | string | Optional 64-character content hash; required for manifest-backed captures |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| screenshot | belongs_to | [[screenshot]] |
| image | has_one_attached | Active Storage blob |

## Enums

- `viewport`: `{ desktop: 0, tablet: 1, mobile: 2 }`, prefix: `viewport_`
- `status`: `{ pending: 0, ready: 1, failed: 2 }`, prefix: `status_`

## Validations

- `viewport`: unique within `screenshot_id`
- `width`, `height`: integer > 0 when present
- `image`: PNG or JPEG, max 20MB
- `content_sha256`: normalized SHA-256 hex; required when the parent screenshot belongs to a manifest-backed snapshot and optional for legacy upload paths

## Callbacks

- `after_create_commit :extract_dimensions_later` enqueues `ScreenshotDimensionJob` only when an image is already attached and the image is not ready.
- `after_save :sync_parent_status` and `after_destroy :sync_parent_status` keep the parent [[screenshot]] status derived from child variants.

## Upload Tokens

`ScreenshotImage` generates 5-minute upload tokens keyed on whether its `image` is already attached. The signed upload endpoint still uses the parent screenshot URL shape, but resolves the token back to the exact `ScreenshotImage` so desktop, tablet, and mobile uploads can complete independently.

## Backfill Helpers

- `backfill_from_screenshots!(apply:, logger:)` moves legacy `Screenshot#image` blobs onto `ScreenshotImage(viewport: :desktop)`.
- `rollback_to_screenshots!(apply:, logger:)` moves desktop blobs back to the legacy parent attachment before rolling back the multi-viewport migration.
- Both helpers return struct counters and continue past individual record errors; the migration treats total failure as deploy-blocking.

## Notes

- `ScreenshotImage` intentionally owns `ALLOWED_CONTENT_TYPES` and `MAX_FILE_SIZE`; [[screenshot]] re-exposes them only for the transitional legacy attachment path.
- The database index `index_screenshot_images_on_screenshot_id_and_viewport` enforces one image per viewport per screenshot.
- The FK from screenshot_images to screenshots does not cascade at the database level; parent destroys use Rails `dependent: :destroy` so Active Storage purge callbacks run.

See also: [[models/screenshot]], [[models/annotation]], [[services/annotation-crop-service]], [[data-model]]
