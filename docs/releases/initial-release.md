# Initial source release

- Status: **blocked release candidate**
- Planned server tag: `v1.0.0`
- Source revision: **pending exact 40-character commit**
- Supported predecessor: `none`
- Canonical public CLI tag: **pending immutable tag and compatibility evidence**
- Canonical image manifest: `ghcr.io/ivankuznetsov/screenote@`**pending exact digest**

This document is a release-note template, not a published release or an authorization to create `v1.0.0`.

## Self-hosted operators

- The supported topology is one non-root Screenote application container
  deployed by the ONCE stable release named in the release evidence behind
  ONCE's Kamal Proxy, with four SQLite roles and one durable volume.
- Local private storage is the default. S3-compatible storage, external
  transactional email, and Google/GitHub OAuth are optional ONCE application
  settings.
- Operators install released stock ONCE with
  `curl https://get.once.com | ONCE_INTERACTIVE=false sh`, then deploy the
  image with an explicit hostname and matching `SCREENOTE_BASE_URL`. No
  Screenote-specific installer or administrator setup credential is required.
- The first visitor claims the instance administrator exactly once through a
  transactional single-winner transition. Later admission is project-owner
  invitation only.
- Operators deploy the GHCR `latest` release channel with ONCE automatic
  application updates enabled. `once update HOST` applies the newest release
  immediately; no fork, source checkout, or local build is required.
- Backup, restore, and upgrade use ONCE commands. A normal `latest` backup
  restores data and settings onto the current release; version-pinned rollback
  requires the immutable digest retained in release evidence. No predecessor
  exists for the initial release.

## SaaS operators

- This revision retains the explicit SaaS edition with Stripe, hosted storage,
  email, OAuth, and monitoring requirements. Its hosted Kamal configuration
  supplies four database-role URLs, while the application and release gates
  use Active Record without a fixed adapter contract.
- The bearer-secret hardening migration is a stopped-process cutover. A rolling
  deploy is prohibited: stop and prove every predecessor web/worker process is
  quiesced, execute the digest-pinned backup hook in that exact stopped window,
  verify its backup receipt against the command-generated timestamp and
  challenge plus the database restore point, then run and verify the successor
  migration chain. The cutover does not wrap all migrations in one outer
  transaction; if interrupted, keep the service in maintenance and either
  resume the idempotent, version-aware verification path or restore the verified
  backup before starting a predecessor.

## Stored data and migrations

The release contains identity, invitation, actor-provenance, installation, authentication-token, and OAuth bearer-secret hardening migrations. Some security transformations are irreversible in place, and adapter capabilities determine each migration's transaction boundary. Rollback means restoring the exact pre-upgrade backup set and starting the recorded predecessor image; never start older code against migrated or partially migrated state.

Because this initial supported release has predecessor `none` and the hosted
database is already current, four pre-v1 migration files were rebaselined once
to remove adapter-specific lock SQL without changing their target schemas.
Migration history is append-only beginning with `v1.0.0`; later repairs require
a new timestamp and a tested supported-predecessor upgrade path.

The final release notes must name every migration after the final schema is frozen, state whether it is reversible, and link the tested backup/restore and cutover commands.

## Configuration

The final release notes must include only non-secret configuration names and defaults. They must identify newly required settings, removed settings, optional providers, and the exact CLI tag. Runtime secret values and private paths never belong here.

## Technical release gates still required

See [`PUBLICATION_BLOCKED.md`](PUBLICATION_BLOCKED.md) and the [publication checklist](publication-checklist.md). Until those gates are complete, there is no supported source archive or container image.
