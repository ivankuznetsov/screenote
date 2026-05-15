---
title: Snapshot
type: model
source: app/models/snapshot.rb
created: 2026-05-14
updated: 2026-05-15
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
| git_commit | string | NOT NULL, varchar(40) on Postgres |
| taken_at | datetime | NOT NULL |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| project | belongs_to | [[project]] |
| screenshots | has_many | [[screenshot]] (dependent: nullify) |

## Validations

- `git_commit`: presence, format `GIT_COMMIT_FORMAT` (7-40 lowercase hex chars; mixed-case input is normalized before validation)
- `taken_at`: defaults to current time when omitted; cannot be more than 5 minutes in the future

## Constants

- `GIT_COMMIT_FORMAT = /\A[0-9a-f]{7,40}\z/` -- canonical regex for a valid git commit SHA. `CreateSnapshotTool` matches user input against this before persisting rather than redefining the contract.

## Scopes

- `recent` -- orders by `taken_at DESC, id DESC`. The id tie-break keeps ordering stable across SQLite/Postgres when a `/snapshot` CLI retry creates two rows in the same second.

## Key Methods

- `short_commit` -- first seven characters of `git_commit`.
- `label` -- `YYYY-MM-DD · short_commit`, used by the project-page snapshot sidebar. Date is computed from `taken_at.utc.to_date` so collaborators in different request zones see the same snapshot label.
- `thumbnails_for(pages)` -- returns the newest ready screenshot per page for this snapshot, including preloaded viewport images for project-page rendering.

## Notes

- `screenshots.snapshot_id` is nullable. Existing and ad-hoc screenshots remain outside snapshots.
- Deleting a snapshot nullifies linked screenshots instead of deleting them.
- Duplicate `(project_id, git_commit)` rows are allowed: repeated captures of the same commit at different times are distinct snapshot runs.
- The project page can filter strictly to pages that have screenshots in one selected snapshot. When filtered, each page card's thumbnail switches from the page's `latest_screenshot` to the newest ready screenshot belonging to that snapshot, so the user sees the snapshot-time look (not whatever was uploaded afterward).

See also: [[project]], [[screenshot]], [[page]]
