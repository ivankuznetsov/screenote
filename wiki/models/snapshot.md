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

## Scopes

- `recent` -- newest `taken_at` first.

## Key Methods

- `short_commit` -- first seven characters of `git_commit`.
- `label` -- `YYYY-MM-DD · short_commit`, used by the project-page snapshot sidebar.

## Notes

- `screenshots.snapshot_id` is nullable. Existing and ad-hoc screenshots remain outside snapshots.
- Deleting a snapshot nullifies linked screenshots instead of deleting them.
- The project page can filter strictly to pages that have screenshots in one selected snapshot.

See also: [[project]], [[screenshot]], [[page]]
