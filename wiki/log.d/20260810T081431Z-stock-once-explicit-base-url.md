---
date: 2026-08-10
type: decision
pages: [self-hosting, architecture, decisions, gaps]
---

Replaced the public dependency on an unreleased Screenote-specific ONCE
integration with released stock ONCE. Operators install it with
`curl https://get.once.com | ONCE_INTERACTIVE=false sh`, then deploy
`ghcr.io/ivankuznetsov/screenote:latest` with an explicit host and matching
`SCREENOTE_BASE_URL`. HTTP-only and S3 examples carry the same explicit-origin
contract. Fresh non-root hosts reconnect once before deployment when the ONCE
installer has just added the operator to the Docker group.

The first visitor still atomically claims the administrator without a setup
credential. Automatic application updates remain enabled, and bare
`once update HOST` remains the immediate-update operation. ADR-019 records this
user-directed decision and supersedes ADR-018's installer-specific contract.

Exact-image ONCE deployment, proxy/forwarding, restart, update, backup, restore,
and matching external S3 recovery evidence remain publication gates.

Source: `README.md`, `docs/once-deployment.md`, `docs/self-hosting.md`,
`docs/releases.md`, `docs/releases/PUBLICATION_BLOCKED.md`,
`docs/releases/initial-release.md`, and
`docs/releases/publication-checklist.md`.
