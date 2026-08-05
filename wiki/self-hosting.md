---
title: Self-Hosted Distribution
type: initiative
source: docs/plans/2026-08-05-001-feat-self-hosted-source-release-plan.md
created: 2026-08-05
updated: 2026-08-05
tags: [self-hosting, docker, licensing, storage, release]
---

# Self-Hosted Distribution

**TLDR:** Screenote has an implementation-ready plan for a source-available, single-container self-hosted edition alongside `screenote.ai`. Publication remains blocked on legal, secret-history, and repository-protection evidence.

## Distribution Model

- Future Spin Ltd will publish Screenote under the O'Saasy license.
- One public repository will carry the shared core and an explicitly enabled SaaS capability.
- Tagged releases will provide a prebuilt container image after quality, security, migration, and self-hosted smoke gates pass.
- Public language should use “source-available and self-hostable” because O'Saasy restricts directly competing hosted services.

## Self-Hosted Product Boundary

- The full core product is unlimited and has no Stripe, plan-limit, or license-key dependency. Core includes projects, screenshot and multi-viewport review, annotations and replies, APIs, CLI, MCP, and agent workflows; selling and operating the managed `screenote.ai` service remains SaaS-only.
- The supported first release is one container backed by SQLite and one persistent volume.
- Primary, cache, queue, and cable state use four SQLite files on that volume with WAL, full durability, bounded contention, and primary-state reconciliation for work lost from the separate queue database.
- Local filesystem storage is the default; operator-configured S3-compatible storage is optional.
- The instance is closed and invitation-only. Before claim, a one-time bootstrap token is the only account-creation path and atomically creates its persisted instance administrator. After claim, each project owner may admit collaborators to that project without separate instance-administrator approval.
- Authorization remains project-scoped: an invitation grants access only to its named project, and even the instance administrator does not receive implicit access to every project. The first release introduces no global Team entity. New local users establish durable credentials during invitation acceptance, so SMTP is not required for later sign-in.
- The instance administrator is a singleton recovery role, not a superuser over project content. It can inspect account identity/status, suspend or restore access, revoke sessions, issue single-use expiring local recovery links, and atomically transfer itself to another active account. A documented local-only container command recovers or transfers an inaccessible administrator without reopening bootstrap or creating a second one. Runtime configuration and secrets stay outside the product UI under operator control.
- SMTP, social OAuth, S3, and monitoring are optional. Administrators can copy invitation links when mail is unavailable.
- Screenshot originals and variants are never served through default reusable Active Storage routes. Application-owned proxy routes authenticate an active project principal and recheck membership for every byte request.
- Runtime application, bootstrap, and provider secrets are generated at the documented strength and mounted from restricted Compose secret files. The bootstrap secret can be removed after claim; secrets must not appear in image layers, process arguments, logs, diagnostics, or tracked configuration.
- OAuth and one-time link credentials become digest-only. Project-scoped OAuth is bound only after a user chooses a joined project on a server-owned consent/device screen. The SaaS credential conversion uses a stopped-process maintenance cutover because predecessor containers cannot read transformed rows.

## SaaS Boundary

The same revision must continue to run `screenote.ai` with PostgreSQL, Stripe, hosted object storage, email, OAuth, and monitoring. Self-hosted defaults must not weaken those production requirements.

## Publication Safety

- GitGuardian full-history scanning gates the initial public source. After publication, protected-branch checks gate every default-branch update, and the same fail-closed policy gates tags and images.
- Publication requires no Open GitGuardian incident. Every confirmed credential must be revoked or rotated before resolution, regardless of perceived risk; ignored incidents are limited to documented false positives or non-secret test values proven incapable of authentication.
- Revoked credentials may remain in reviewed history only with documented security and legal approval. Non-revocable secrets, protected personal or confidential data, third-party intellectual property, or unapproved retention require rewritten or replacement history.
- Extending GitGuardian to other eligible public repositories is a separate initiative and does not authorize private-repository access.
- Release candidates build AMD64 and ARM64 OCI layouts once, import them into a trusted ephemeral scanner target, and pass both GitGuardian secret scanning and a pinned Critical/High vulnerability policy before any tag or registry mutation. Promotion is resumable only when every existing object exactly matches retained evidence.
- Public evidence contains hashes, opaque identifiers, versions, and dispositions only. Credential inventories, incident detail, vulnerability findings, and waivers remain in a restricted evidence store.

## Scope

The first release supports sequential upgrades between named adjacent releases and retains immutable images for each supported hop. Supported backup/restore commands quiesce the service, bind the full volume and local/S3 blob inventory to an authenticated-encrypted manifest, and encrypt to an operator-held age identity stored outside the host and backup. Rollback restores the exact pre-upgrade set with the recorded predecessor image and may discard later writes; an older image must never open migrated state. It defers self-hosted PostgreSQL, high availability, clustering, enterprise SSO, SaaS import/export, storage migration tooling, and in-product updates. See [[plans-and-initiatives]] and the implementation-ready plan at `docs/plans/2026-08-05-001-feat-self-hosted-source-release-plan.md`.

See also: [[architecture]], [[dependencies]], [[decisions]], [[testing-and-ci]]
