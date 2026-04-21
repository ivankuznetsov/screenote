---
title: Session
type: model
source: app/models/session.rb
created: 2026-04-10
updated: 2026-04-10
tags: [model, auth, session]
---

# Session

TLDR: Database-backed user sessions with IP and user agent tracking. Managed by rails_simple_auth. Supports expiry-based cleanup.

Source: `app/models/session.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| user_id | integer | NOT NULL, FK to users |
| ip_address | string | Client IP at session creation |
| user_agent | string | Browser user agent string |
| created_at | datetime | Indexed for expiry queries |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| user | belongs_to | [[user]] |

## Scopes

- `recent` -- `order(created_at: :desc)`
- `active` -- Sessions created within `RailsSimpleAuth.configuration.session_expiry` window
- `expired` -- Sessions older than the expiry window

## Key Methods

- `self.cleanup_expired!` -- Deletes all expired sessions

## Notes

- Session expiry duration is configured in `config/initializers/rails_simple_auth.rb`.
- The `created_at` index supports efficient expired session cleanup queries.

See also: [[user]]
