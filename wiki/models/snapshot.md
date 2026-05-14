---
title: Snapshot
type: model
source: app/models/snapshot.rb
created: 2026-05-14
updated: 2026-05-14
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
| git_commit | string | NOT NULL, max 64 |
| taken_at | datetime | NOT NULL |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| project | belongs_to | [[project]] |
| screenshots | has_many | [[screenshot]] (dependent: nullify) |

## Validations

- `git_commit`: presence, length max 64
- `taken_at`: presence

## Constants

- `GIT_COMMIT_FORMAT = /\A[0-9a-f]{7,40}\z/` -- canonical regex for a valid git commit SHA. Callers (e.g. `CreateMultiViewportScreenshotTool`) match against this rather than redefining the contract.

## Scopes

- `recent` -- orders by `taken_at DESC, id DESC`. The id tie-break keeps ordering stable across SQLite/Postgres when a `/snapshot` CLI retry creates two rows in the same second.

## Key Methods

- `short_commit` -- first seven characters of `git_commit`.
- `label` -- `YYYY-MM-DD · short_commit`, used by the project-page snapshot sidebar. Date is computed via `taken_at.in_time_zone.to_date` so it reflects the request's `Time.zone` (the dev-facing CLI expects the commit date in their local zone).

## Notes

- `screenshots.snapshot_id` is nullable. Existing and ad-hoc screenshots remain outside snapshots.
- Deleting a snapshot nullifies linked screenshots instead of deleting them.
- The project page can filter strictly to pages that have screenshots in one selected snapshot. When filtered, each page card's thumbnail switches from the page's `latest_screenshot` to the newest ready screenshot belonging to that snapshot, so the user sees the snapshot-time look (not whatever was uploaded afterward).

See also: [[project]], [[screenshot]], [[page]]
