---
title: ProjectInvitation
type: model
source: app/models/project_invitation.rb
created: 2026-04-10
updated: 2026-04-10
tags: [model, collaboration, invitation, email]
---

# ProjectInvitation

TLDR: Email-based invitation to join a project. Uses Rails token generation with 7-day expiry. Enforces member limits based on the project owner's subscription plan.

Source: `app/models/project_invitation.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| project_id | integer | NOT NULL, FK to projects |
| inviter_id | integer | NOT NULL, FK to users |
| email | string | NOT NULL, normalized to lowercase |
| status | integer | Enum: pending(0), accepted(1). Default: pending |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| project | belongs_to | [[project]] |
| inviter | belongs_to | [[user]] |

## Enums

- `status`: `{ pending: 0, accepted: 1 }`

## Validations

- `email`: presence, email format (URI::MailTo::EMAIL_REGEXP)
- `email`: uniqueness scoped to project_id for pending invitations only
- Custom: `not_already_member` -- prevents inviting existing project members

## Normalizations

- `email`: stripped and downcased

## Token Generation

- `generates_token_for :accept, expires_in: 7.days` -- Token invalidates when status changes from pending to accepted (status is part of the fingerprint)

## Key Methods

- `accept!(user)` -- Transactional with pessimistic lock on project. Checks member limit via `project.creator.can_invite_member?`. Updates status to accepted, creates ProjectMembership with `:member` role. Raises `MemberLimitExceeded` if over limit.

## Custom Exceptions

- `MemberLimitExceeded` -- Raised when the project owner's plan doesn't allow more members

## Notes

- The invitation flow handles both existing and new users. New users get an account created automatically with a random password and immediate email confirmation.
- Invitations can be cancelled (destroyed) while pending, but not after acceptance.

See also: [[project]], [[project-membership]], [[user]], [[controllers/web-controllers]]
