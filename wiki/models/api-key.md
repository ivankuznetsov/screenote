---
title: ApiKey
type: model
source: app/models/api_key.rb
created: 2026-04-10
updated: 2026-07-12
tags: [model, auth, api, security]
---

# ApiKey

TLDR: Project-scoped bearer tokens for REST API authentication. Tokens are SHA-256 hashed at rest, displayed once on creation, and support soft-delete via revocation.

Source: `app/models/api_key.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| name | string | NOT NULL, max 255 |
| project_id | integer | NOT NULL, FK to projects |
| token_digest | string | NOT NULL, unique, SHA-256 hash of raw token |
| token_prefix | string | First 12 chars of raw token (for identification) |
| revoked_at | datetime | Soft-delete timestamp |
| last_used_at | datetime | Throttled to 5-minute updates |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| project | belongs_to | [[project]] |

## Validations

- `token_digest`: presence, uniqueness
- `name`: presence, length max 255

## Scopes

- `active` -- `where(revoked_at: nil)`
- `revoked` -- `where.not(revoked_at: nil)`

## Callbacks

- `before_validation :generate_token, on: :create` -- Generates `sk_proj_` prefixed token, stores hash and prefix

## Key Methods

- `self.find_by_token(token)` -- Looks up by SHA-256 digest of the provided token
- `revoke!` -- Soft-deletes by setting `revoked_at` (idempotent)
- `revoked?` -- Checks if revoked_at is present
- `touch_last_used!` -- Throttled: only updates `last_used_at` if more than 5 minutes have passed since last update

## Transient Attributes

- `raw_token` (attr_accessor) -- The plaintext token, only available immediately after creation. Never persisted.

## Read-Only Columns

- `token_digest`, `token_prefix` -- Declared via `attr_readonly`, cannot be changed after creation

## Notes

- Token format: `sk_proj_` + 48 hex chars (24 random bytes)
- The `raw_token` is flashed to the user once via `flash[:api_key_token]` in the controller and never shown again.
- Used by `Api::BaseController` for bearer token authentication on REST API endpoints.
- Also used as the author of annotation comments when agents resolve/reopen annotations.
- `20260712153000_repair_legacy_api_key_token_storage` repairs databases that ran the original plaintext-token create migration before it was rewritten. It hashes any legacy values, removes the plaintext column, and is intentionally irreversible.

See also: [[project]], [[controllers/api-controllers]], [[annotation-comment]]
