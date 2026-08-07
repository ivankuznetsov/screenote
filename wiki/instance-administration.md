---
title: Instance Administration
type: architecture
source: app/services/instance_accounts
created: 2026-08-06
updated: 2026-08-06
tags: [self-hosting, administration, recovery, security]
---

# Instance Administration

**TLDR:** A claimed self-hosted installation has one active singleton administrator with narrow account-recovery powers and no project-content bypass.

Every operation resolves authority from the locked `Installation` row, then locks involved users in ascending ID order. Mutation services apply `DatabaseRetry` only outside their primary transaction and append their successful action—or an authenticated denial—to `InstallationAuditEvent` in that same transaction. Transfer updates the one administrator reference atomically; the current administrator cannot be suspended.

The account list plucks only user ID, email, active/suspended state, and creation time. It never joins projects. Suspending or revoking locks the credential graph in the global order: installation, users, referenced projects, pending invitations, memberships, then credentials. It deletes browser sessions and device grants; revokes OAuth grants/tokens and API keys issued by the user; cancels user authentication links and pending invitations issued by the user. Restore permits future authentication but never revives a credential.

Recovery uses the shared digest-only `AuthenticationToken` lifecycle with purpose `account_recovery`, immutable administrator issuer provenance, an exact 15-minute expiry, one outstanding generation, and a 24-hour terminal-metadata retention floor. The raw secret appears only in the one response or operator stdout as a URL fragment. HTML issuance loads the sterile account list before committing or superseding a credential, while the Turbo response renders the one-time presentation directly, so a post-commit list failure cannot hide the only copy. The reveal is marked `data-turbo-temporary` beneath private `no-store` headers, so Turbo removes it before snapshot caching. Exchange stores only token ID and purpose in the encrypted session; consumption rechecks the current active issuer, revokes old credentials, changes only the local password, consumes once, and appends its audit event atomically. Retryable database or authority failures return `503 Service Unavailable` without discarding that tokenless session context; only a terminally invalid recovery clears it and renders the invalid-link response. Instance-account mutation and list infrastructure failures likewise return 503 with retry guidance instead of being mislabeled as authorization or validation failures.

Session creation, account-principal OAuth consent, device approval, token exchange, API-key creation, and revocation all serialize through the resource-owner user lock. This prevents a credential created after a suspension scan from surviving and becoming usable after restore.

Operator commands are `bin/rails screenote:instance:recover_administrator` and `bin/rails 'screenote:instance:transfer_administrator[email@example.test]'`. They are self-hosted-only, call the same services with the `local_operator` audit channel, create no users, and require no SMTP or network service.

See also: [[self-hosting]], [[models/authentication-token]], [[models/installation-audit-event]], [[models/user]], [[data-model]]
