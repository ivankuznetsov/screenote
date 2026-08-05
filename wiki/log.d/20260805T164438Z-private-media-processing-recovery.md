---
title: Private media and processing recovery
type: changelog
created: 2026-08-05
tags: [self-hosting, active-storage, security, jobs]
---

- Disabled reusable Active Storage delivery and direct-upload routes in favor of project-membership-checked application media URLs.
- Unified signed and manifest image ingestion behind bounded byte, type, dimension, pixel-count, and decoder-concurrency validation.
- Added startup and recurring reconciliation for committed screenshot processing work that could not reach Solid Queue.
- Updated [[self-hosting]] with the concrete media and recovery contract.
