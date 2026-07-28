---
title: ScreenshotImage
type: model
source: app/models/screenshot_image.rb
created: 2026-05-14
updated: 2026-07-28
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
| expected_content_type | string | Prepared PNG/JPEG type for content-bound CLI uploads |
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
- `expected_content_type`: normalized `image/png` or `image/jpeg`; required alongside content SHA for manifest-backed captures

## Callbacks

- `after_create_commit :ensure_dimension_processing` enqueues `ScreenshotDimensionJob` only when an image is already attached and the image is not ready. Manifest replay reuses the same public method.
- `after_save :sync_parent_status` and `after_destroy :sync_parent_status` keep the parent [[screenshot]] status derived from child variants.
- Manifest replay schedules attached pending images again to recover a lost enqueue. `ScreenshotDimensionJob` keys Solid Queue concurrency by ScreenshotImage and attachment blob generation: duplicate work for one blob is discarded, replacement blobs remain schedulable, and completion rechecks the generation before updating dimensions.
- After a generation-checked dimension update commits and makes the logical screenshot ready, `ScreenshotDimensionJob` reloads the parent and enqueues `ScreenshotThumbnailJob` for its current primary image. Desktop remains primary even when a mobile or tablet sibling finishes last.

## Overview Thumbnails

The `image` attachment declares three named, tracked Active Storage variants:

| Name | Output | Consumer |
|------|--------|----------|
| `page_card_1x` | 480x270, `resize_to_fill` | Page cards at standard density |
| `page_card_2x` | 960x540, `resize_to_fill` | Page cards at high density |
| `project_strip` | 240x160, `resize_to_fill` | Compact project previews |

`ScreenshotThumbnailJob` processes these variants outside request rendering. It is concurrency-limited per ScreenshotImage/blob generation and revalidates the attached blob, child and parent readiness, and exact current primary-image identity before processing. Stale replacements, siblings that are no longer primary, pending/failed records, and unattached rows exit without changing capture state. Existing tracked variant records make repeated jobs no-ops.

`bin/rails screenshots:warm_thumbnails` scans existing rows in batches and is a dry-run unless `APPLY=1` is supplied. Its summary reports `candidates`, `skipped`, `processed`, and `failed`; `BATCH_SIZE` defaults to 1000. Apply mode invokes the same job synchronously for exact accounting and remains idempotent because tracked records are reused. Asynchronous processing wraps only the variant-processing boundary in a three-attempt retry; a partial retry skips already tracked variant digests.

Overview requests never call `processed` or enqueue thumbnail work. They emit
representation URLs only when all three named variants are found in the current
blob's already-preloaded tracked variant records; otherwise page cards show the
thumbnail-processing placeholder and project strips omit the thumbnail. Project
lists render `project_strip` at 120x80 CSS/intrinsic dimensions from its 240x160
source, while page cards emit 480w and 960w candidates with a grid-aware
`sizes` contract and 480x270 intrinsic dimensions. Controllers and model scopes
preload the child image attachment, source blob, tracked variant records, and
variant output attachments in fixed query batches, including snapshot-filtered
cards.

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
