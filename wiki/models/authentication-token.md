---
title: AuthenticationToken
type: model
source: app/models/authentication_token.rb
created: 2026-08-05
updated: 2026-08-06
tags: [model, authentication, security, token]
---

# AuthenticationToken

TLDR: Digest-only persistence for purpose-bound authentication links. A row contains public derivation metadata and lifecycle state, never the raw 32-byte credential.

Purposes are invitation (bound only to `ProjectInvitation`) and password reset, magic link, email confirmation, or account recovery (bound only to `User`). Immutable fields are purpose, subject, positive generation, random 64-hex derivation ID, versioned 46-character derivation-key ID, lowercase 64-hex SHA-256 digest, and expiry.

Account-recovery rows additionally require immutable `issued_by_user_id` provenance; every other purpose forbids it. `AuthenticationLinks::Issuer` enforces that exact presence/absence contract before persistence, while `attr_readonly` and database constraints prevent later reassignment. Recovery consumption re-locks the singleton installation, subject, and issuer and accepts the link only while its issuer is still the current active instance administrator. It atomically wins the token transition before changing a password or revoking credentials, so a lost consumption race commits no account mutation. The provenance migration is deliberately irreversible because dropping the issuer would make outstanding recovery authority unverifiable.

State is outstanding, consumed, superseded, or cancelled. Outstanding rows require a null `terminal_at`; terminal rows require `terminal_at >= created_at`. Atomic `transition_to!` updates only a still-outstanding row. Separate partial indexes enforce one outstanding token and unique generations for each exact user/invitation purpose.

See also: [[data-model]], [[schema-evolution]], [[decisions]], [[instance-administration]], [[models/user]], [[models/project-invitation]]
