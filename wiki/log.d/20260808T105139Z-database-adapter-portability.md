---
date: 2026-08-08
type: decision
pages: [architecture, decisions, testing-and-ci, schema-evolution, data-model, self-hosting, gaps, gems, controllers/oauth-controllers, models/project-membership, models/api-key, models/snapshot]
---

Separated Screenote's Active Record application boundary from deployment
topology. Required source CI and release qualification no longer require a
database adapter or server version; the exact-image SaaS boot checks remain on
AMD64 and ARM64 and exercise four role-specific database URLs. Supported
self-hosting still uses SQLite, while the hosted Kamal configuration may keep
PostgreSQL.

Source CI now has one adapter-neutral `CI / test` job. It removes the separate
SQLite/PostgreSQL application-test jobs and PostgreSQL-only source matrix
modes, fixtures, and assertions; Active Record remains the application and
test boundary.

Admission serialization now uses 256 bounded durable lock stripes and Active
Record no-op updates, so it works even before a User exists without storing the
normalized address, an address digest, or an adapter-specific lock primitive.

The stopped-process credential cutover now follows each migration's supported
transaction behavior instead of promising one outer transaction across the
chain. Its recovery contract is maintenance-mode quiescence, verified
backup/restore, migration-version-aware idempotent resume, and final stored
credential/runtime verification.

The initial predecessor-none release also permits one bounded pre-v1
portability rebaseline of four migration files because the hosted database is
already current. Migration history becomes append-only at `v1.0.0`.

This decision supersedes current wording that treated PostgreSQL as a
release-qualification requirement; historical plan and log entries remain
unchanged.
