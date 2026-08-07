---
title: User
type: model
source: app/models/user.rb
created: 2026-04-10
updated: 2026-08-05
tags: [model, auth, user, subscription]
---

# User

TLDR: Central identity model. Includes auth concerns from rails_simple_auth (Authenticatable, Confirmable, MagicLinkable, OAuthConnectable). Owns projects, holds subscriptions, creates annotations.

Source: `app/models/user.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| email | string | NOT NULL, unique index |
| password_digest | string | NOT NULL (bcrypt) |
| confirmed_at | datetime | Email confirmation timestamp |
| oauth_provider | string | "google" or "github" |
| oauth_uid | string | Provider-specific user ID |
| access_status | integer | Enum: active(0), suspended(1); checked in the database |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| sessions | has_many | [[session]] (dependent: destroy) |
| owned_projects | has_many | [[project]] (foreign_key: user_id, dependent: destroy) |
| project_memberships | has_many | [[project-membership]] (dependent: destroy) |
| projects | has_many through | [[project]] (via project_memberships) |
| annotations | has_many | [[annotation]] (dependent: destroy) |
| subscription | has_one | [[subscription]] (dependent: destroy) |
| authentication_tokens | has_many | [[authentication-token]] (dependent: destroy) |
| installation_audit_events_as_actor | has_many | [[installation-audit-event]] (restrict deletion) |
| installation_audit_events_as_target | has_many | [[installation-audit-event]] (restrict deletion) |

## Includes

- `RailsSimpleAuth::Models::Concerns::Authenticatable`
- `RailsSimpleAuth::Models::Concerns::Confirmable`

Legacy raw signed-token helpers are explicitly undefined. App-owned authentication-link services issue digest-only password-reset, magic-link, confirmation, invitation, and account-recovery credentials.

## Key Methods

- `pro?(deployment:)` -- Returns true only when billing is enabled and the user has an active Pro subscription; it does not query subscriptions in self-hosted mode
- `can_create_project?(deployment:)` -- Unlimited without a query in self-hosted mode; SaaS Pro users are unlimited and free users retain `Subscription::FREE_PROJECT_LIMIT`
- `can_invite_member?(project, deployment:)` -- Unlimited without a query in self-hosted mode; SaaS Pro users are unlimited and free users retain `Subscription::FREE_MEMBER_LIMIT`
- `saas_operator?(deployment:)` -- True only in SaaS mode when the normalized email matches the boot-validated `SCREENOTE_SAAS_OPERATOR_EMAIL`; there is no generic `admin?` compatibility alias
- `assign_oauth_attributes(auth_hash)` -- Sets oauth_provider and oauth_uid from OmniAuth hash
- `self.find_by_oauth(provider, uid)` -- Finds user by OAuth provider + UID
- `access_active?` / `active_for_authentication?` -- Shared active-account predicate; false for suspended users

## Validations

Inherited email/password rules are supplemented by canonical provider/UID pairing and scoped provider identity uniqueness. Database CHECKs and indexes enforce canonical normalized email, paired normalized OAuth identity, and active/suspended status for direct writes.

See also: [[subscription]], [[project]], [[project-membership]], [[session]]
