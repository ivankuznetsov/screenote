---
date: 2026-08-09
type: decision
pages: [self-hosting, architecture, decisions, gaps, api-cli, gems]
---

Replaced the public self-hosted Kamal workflow with ONCE's stable channel. Operators
deploy the exact `vX.Y.Z@sha256:...` GHCR release identity with automatic
updates disabled and supply the canonical base URL plus one-time bootstrap
token through the ONCE CLI. A fork, source checkout, tracked self-hosted Kamal
configuration, and custom Kamal wrapper are no longer part of public setup;
Kamal remains isolated to hosted `screenote.ai`.

Recorded the runtime contract behind that path: the release image defaults to
the self-hosted edition, TLS enabled, and narrow proxy trust; ONCE's explicit
HTTP mode overrides that TLS default and must match the canonical URL scheme.
ONCE's one durable volume is mounted at both `/storage` and `/rails/storage`,
its Email settings map to the generic SMTP configuration, and startup
reconciliation is accepted by Solid Queue before the server begins instead of
repairing the entire corpus inline.

ONCE pauses the application while copying local volume state. External S3
objects remain a separate operator/provider recovery responsibility. The first
release sentinel now requires retained evidence for an exact-image deploy,
restart, explicit update, backup, and restore through the supported ONCE
release named in the evidence. The
custom-image TUI's inability to supply Screenote's required first-boot
variables remains a documented CLI-only installation limitation.

Source: `Dockerfile`, `bin/docker-entrypoint`,
`app/jobs/reconcile_screenshot_processing_job.rb`,
`lib/screenote/deployment.rb`, `docs/once-deployment.md`,
`config/deploy.saas.yml`, `docs/releases/PUBLICATION_BLOCKED.md`,
`wiki/api-cli.md`, and `wiki/gems.md`.
