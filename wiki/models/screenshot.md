---
title: Screenshot
type: model
source: app/models/screenshot.rb
created: 2026-04-10
updated: 2026-04-10
tags: [model, screenshot, image, active-storage]
---

# Screenshot

TLDR: An uploaded image (PNG or JPEG, max 20MB) that serves as the canvas for annotations. Has a status lifecycle (pending -> ready/failed) and generates single-use upload tokens for the MCP signed-upload workflow.

Source: `app/models/screenshot.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| title | string | NOT NULL, max 255 |
| page_id | integer | NOT NULL, FK to pages |
| status | integer | Enum: pending(0), ready(1), failed(2). Default: pending |
| width | integer | Pixel width (extracted async) |
| height | integer | Pixel height (extracted async) |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| page | belongs_to | [[page]] |
| project | has_one through | [[project]] (via page) |
| annotations | has_many | [[annotation]] (dependent: destroy) |
| image | has_one_attached | Active Storage (Rabata S3 in production) |

## Enums

- `status`: `{ pending: 0, ready: 1, failed: 2 }`

## Validations

- `title`: presence, length max 255
- `width`, `height`: integer > 0 (allow nil for pending uploads)
- `image`: content type must be PNG or JPEG, max 20MB

## Callbacks

- `after_create_commit :extract_dimensions_later` -- Enqueues `ScreenshotDimensionJob` to extract width/height from the image

## Token Generation

- `generates_token_for :upload, expires_in: 5.minutes` -- Single-use upload token. Invalidates once an image is attached (the token includes `image.attached?.to_s` in its fingerprint).

## Constants

- `ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg]`
- `MAX_FILE_SIZE = 20.megabytes`

## Notes

- The two-step upload flow: (1) Create screenshot record via MCP/API, get upload URL + token, (2) PUT binary data to `/api/screenshots/:id/upload` with the token. See [[decisions]] ADR-011.
- Dimension extraction is async to avoid blocking the upload response.

See also: [[page]], [[annotation]], [[services/annotation-crop-service]]
