---
title: Snapshot
type: model
source: app/models/snapshot.rb
created: 2026-05-14
updated: 2026-08-08
tags: [model, snapshot, project, screenshot]
---

# Snapshot

TLDR: Captures a project at a moment in time for `/snapshot` runs. A snapshot stores the git commit and capture timestamp, and screenshots uploaded during that run optionally point back to it.

Source: `app/models/snapshot.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| project_id | integer | NOT NULL, FK to projects |
| git_commit | string | NOT NULL, limit 40 |
| taken_at | datetime | NOT NULL |
| manifest_digest | string | Optional 64-character SHA-256 identity for resumable CLI captures |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| project | belongs_to | [[project]] |
| screenshots | has_many | [[screenshot]] (dependent: nullify) |
| screenshot_images | has_many through | [[models/screenshot-image]] via screenshots |

## Validations

- `git_commit`: presence, format `GIT_COMMIT_FORMAT` (7-40 lowercase hex chars; mixed-case input is normalized before validation)
- `taken_at`: defaults to current time when omitted; cannot be more than 5 minutes in the future
- `manifest_digest`: optional for legacy/MCP rows; normalized to lowercase SHA-256 hex and unique within a project when present

## Constants

- `GIT_COMMIT_FORMAT = /\A[0-9a-f]{7,40}\z/` -- canonical regex for a valid git commit SHA. `CreateSnapshotTool` matches user input against this before persisting rather than redefining the contract.
- `SHA256_FORMAT` and `SHA256_ERROR_MESSAGE` define the shared manifest/content digest contract used by Snapshot, Screenshot, and ScreenshotImage.

## Scopes

- `recent` -- orders by `taken_at DESC, id DESC`. The id tie-break keeps ordering stable across supported databases when a `/snapshot` CLI retry creates two rows in the same second.

## Key Methods

- `short_commit` -- first seven characters of `git_commit`.
- `label` -- `YYYY-MM-DD · short_commit`, used by the project-page snapshot sidebar. Date is computed from `taken_at.utc.to_date` so collaborators in different request zones see the same snapshot label.
- `thumbnails_for(pages)` -- returns the newest ready screenshot per page for this snapshot, including preloaded viewport images for project-page rendering.
- `manifest_backed?` -- true when the snapshot carries a resumable manifest identity.
- `aggregate_state` -- derives `awaiting_upload`, `processing`, `failed`, or `ready` from expected ScreenshotImage attachments and statuses.

## Notes

- `screenshots.snapshot_id` is nullable. Existing and ad-hoc screenshots remain outside snapshots.
- Deleting a snapshot nullifies linked screenshots instead of deleting them.
- Duplicate `(project_id, git_commit)` rows are allowed: repeated captures of the same commit at different times are distinct snapshot runs.
- A partial unique index on `(project_id, manifest_digest)` deduplicates only manifest-backed runs; legacy duplicate commit snapshots remain valid.
- MCP `taken_at` input must include `Z` or an explicit `+/-HH:MM` offset; offset-less timestamps are rejected instead of being interpreted in the server timezone.
- The project page can filter strictly to pages that have screenshots in one selected snapshot. When filtered, each page card's thumbnail switches from the page's `latest_screenshot` to the newest ready screenshot belonging to that snapshot, so the user sees the snapshot-time look (not whatever was uploaded afterward).

See also: [[project]], [[screenshot]], [[page]]
