---
title: AnnotationComment
type: model
source: app/models/annotation_comment.rb
created: 2026-04-10
updated: 2026-04-10
tags: [model, annotation, comments, threading]
---

# AnnotationComment

TLDR: Threaded comments on annotations with an action enum tracking whether the comment is a regular comment, a resolve action, or a reopen action. Authored by either a user or an API key (agent), but not both.

Source: `app/models/annotation_comment.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| annotation_id | integer | NOT NULL, FK to annotations (ON DELETE CASCADE) |
| user_id | integer | FK to users (ON DELETE SET NULL) |
| api_key_id | integer | FK to api_keys (ON DELETE SET NULL) |
| body | text | NOT NULL, max 5000 chars |
| action | integer | Enum: comment(0), resolved(1), reopened(2). Default: comment |
| notified_at | datetime | When digest notification was sent for this comment |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| annotation | belongs_to | [[annotation]] |
| user | belongs_to | [[user]] (optional) |
| api_key | belongs_to | [[api-key]] (optional) |

## Enums

- `action`: `{ comment: 0, resolved: 1, reopened: 2 }`

## Validations

- `body`: presence, length max 5000
- Custom: `has_author` -- exactly one of user_id or api_key_id must be present (XOR constraint)

## Notes

- Comments with action `:resolved` or `:reopened` are created transactionally by `Annotation#resolve!` and `Annotation#reopen!`, not directly by controllers.
- The `notified_at` field is used by the hourly digest notification system to track which comments have been included in emails. The composite index `(action, notified_at)` supports efficient queries for unnotified resolved/reopened comments.
- The XOR author validation ensures a comment is attributed to exactly one source: a human user or an AI agent (via API key).

See also: [[annotation]], [[user]], [[api-key]]
