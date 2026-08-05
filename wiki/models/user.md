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

## Includes

- `RailsSimpleAuth::Models::Concerns::Authenticatable`
- `RailsSimpleAuth::Models::Concerns::Confirmable`
- `RailsSimpleAuth::Models::Concerns::MagicLinkable`
- `RailsSimpleAuth::Models::Concerns::OAuthConnectable`

## Key Methods

- `pro?` -- Returns true if user has an active Pro subscription (delegates to `subscription.active_pro?`)
- `can_create_project?` -- Pro users: unlimited. Free users: limited to `Subscription::FREE_PROJECT_LIMIT` (1) owned projects
- `can_invite_member?(project)` -- Pro users: unlimited. Free users: limited to `Subscription::FREE_MEMBER_LIMIT` (1) member per project
- `saas_operator?` / compatibility alias `admin?` -- True only in SaaS mode when the normalized email matches the boot-validated `SCREENOTE_SAAS_OPERATOR_EMAIL`
- `assign_oauth_attributes(auth_hash)` -- Sets oauth_provider and oauth_uid from OmniAuth hash
- `self.find_by_oauth(provider, uid)` -- Finds user by OAuth provider + UID

## Validations

Inherited from rails_simple_auth concerns (email format, password presence, etc.).

See also: [[subscription]], [[project]], [[project-membership]], [[session]]
