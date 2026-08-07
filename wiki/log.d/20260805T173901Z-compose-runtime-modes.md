---
title: Self-hosted Compose runtime modes
type: changelog
created: 2026-08-05
tags: [self-hosting, docker, secrets, readiness]
---

- Made the base Compose file the supported claimed local-storage mode, with the bootstrap credential isolated in a removable first-claim overlay.
- Added additive S3, SMTP, Google OAuth, GitHub OAuth, and Honeybadger overlays whose credentials are restricted files rather than environment values.
- Added local-only generic readiness across the four SQLite roles, persistent-volume writability, and selected storage configuration while preserving `/up` as liveness.
- Bounded Thruster request bodies at 30 MiB and added a final-image replacement/persistence smoke workflow.
- Updated [[self-hosting]] with the operational runtime contract.
