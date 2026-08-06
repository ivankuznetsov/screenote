# Initial source release

- Status: **blocked release candidate**
- Planned server tag: `v1.0.0`
- Supported predecessor: `none`
- Canonical public CLI tag: **pending immutable tag and compatibility evidence**
- Canonical image manifest: **pending exact digest**

This document is a release-note template, not a published release or an authorization to create `v1.0.0`.

## Self-hosted operators

- The supported topology is one non-root Screenote container with four SQLite roles and one durable volume.
- Local private storage is the default. S3-compatible storage, SMTP, Google/GitHub OAuth, and monitoring are optional explicit overlays.
- A fresh instance is claimed exactly once with a removable bootstrap-secret overlay. Later admission is project-owner invitation only.
- The core product is unlimited and has no billing, Stripe, or license-key dependency.
- Backup, restore, upgrade, and rollback must use the commands and immutable digest published with the final release. No predecessor exists for the initial release.

## SaaS operators

- This revision retains the explicit SaaS edition with PostgreSQL, Stripe, hosted storage, email, OAuth, and monitoring requirements.
- The bearer-secret hardening migration is a stopped-process cutover. A rolling deploy is prohibited: stop and prove every predecessor web/worker process is quiesced, execute the pre-reviewed digest-pinned backup hook in that exact stopped window, verify its new private evidence against the command-generated timestamp and challenge plus the database restore point, migrate once with the successor image, and start only the successor revision.

## Stored data and migrations

The release contains identity, invitation, actor-provenance, installation, authentication-token, and OAuth bearer-secret hardening migrations. Some security transformations are irreversible in place. Rollback means restoring the exact pre-upgrade backup set and starting the recorded predecessor image; never start older code against migrated state.

The final release notes must name every migration after the final schema is frozen, state whether it is reversible, and link the tested backup/restore and cutover commands.

## Configuration

The final release notes must include only non-secret configuration names and defaults. They must identify newly required settings, removed settings, optional providers, and the exact CLI tag. Runtime secret values and private paths never belong here.

## Publication evidence still required

See [`PUBLICATION_BLOCKED.md`](PUBLICATION_BLOCKED.md) and the [publication checklist](publication-checklist.md). Until those gates are complete, there is no supported source archive or container image.
