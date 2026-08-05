---
title: Deployment topology preflight
type: changelog
created: 2026-08-05
tags: [self-hosting, deployment, database, security]
---

- Added a standalone deployment preflight before `db:prepare`, preventing an edition change from selecting and initializing an unrelated database topology before persisted identity checks run.
- SaaS startup now refuses a mounted self-hosted primary, while self-hosted startup refuses retained SaaS database-role settings and verifies an existing SQLite installation's edition, storage service, storage namespace, and applicable bootstrap digest through a read-only connection.
- Added real entrypoint-ordering tests that use the production SQLite-versus-PostgreSQL topology boundary and prove identity drift stops before `db:prepare` can apply a pending migration.
- Updated [[self-hosting]] with the two-stage deployment identity contract.
