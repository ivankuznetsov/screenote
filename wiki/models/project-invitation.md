---
title: ProjectInvitation
type: model
source: app/models/project_invitation.rb
created: 2026-04-10
updated: 2026-08-06
tags: [model, collaboration, invitation, email]
---

# ProjectInvitation

TLDR: Email-based invitation to join a project. Uses a digest-only, single-use authentication link with 7-day expiry and enforces member limits only in billing-enabled SaaS.

Source: `app/models/project_invitation.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| project_id | integer | NOT NULL, FK to projects |
| inviter_id | integer | NOT NULL, FK to users |
| email | string | NOT NULL, normalized to lowercase |
| status | integer | Enum: pending(0), accepted(1), cancelled(2). Default: pending |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| project | belongs_to | [[project]] |
| inviter | belongs_to | [[user]] |
| authentication_tokens | has_many | [[authentication-token]] |

## Enums

- `status`: `{ pending: 0, accepted: 1, cancelled: 2 }`

## Validations

- `email`: presence, email format (URI::MailTo::EMAIL_REGEXP)
- `email`: uniqueness scoped to project_id for pending invitations only
- Custom: `not_already_member` -- prevents inviting existing project members

## Normalizations

- `email`: stripped and downcased
- Database CHECK: stored email is canonical lowercase/trimmed
- Database partial unique index: one pending row per project and normalized email; terminal accepted/cancelled history is retained

## Token Generation

- `ProjectInvitations::Issue` serializes owner authority, membership limits, invitation replacement, and `AuthenticationLinks::Issuer` generation in the locked admission transaction.
- The raw credential is deterministically re-presentable only while its digest-only `AuthenticationToken` remains outstanding and its derivation key is retained. Acceptance exchanges it into a tokenless session context before any identity proof.
- A successful issuance reports mail delivery separately as `queued`, `failed`, or `not_requested`. Enqueue failure keeps the committed private link and directs the owner to copy it instead of claiming that mail was sent.

## Key Methods

- `ProjectInvitations::Accept` -- Revalidates the exact exchanged token, identity proof, locked inviter/owner authority, membership set, and optional SaaS limit before atomically creating membership and consuming the token.
- `ProjectInvitations::Cancel` -- Cancels the pending row and its exact outstanding authentication link under the same authority order.

## Notes

- Invitation acceptance requires an explicit session, local-password, or verified-provider identity proof. Provider hashes accept string or symbol keys, but an explicitly present string key is authoritative so contradictory duplicates cannot turn a false verification claim into true.
- The flow handles both existing and new users, serializes issuance, acceptance, and cancellation, and retains accepted or cancelled terminal rows for auditability.
- Retryable acceptance results with no embedded invitation revalidate the retained tokenless context before rendering, so a transient failure never presents a valid invitation as invalid.

See also: [[project]], [[project-membership]], [[user]], [[controllers/web-controllers]]
