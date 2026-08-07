---
title: Active Storage upload commit lifecycle
type: changelog
created: 2026-08-05
tags: [self-hosting, active-storage, testing, transactions]
---

- Staged validated screenshot bytes in the selected storage service before attaching the Blob, so committed attachment metadata never depends on a closed request tempfile.
- Removed staged objects when a concurrent upload wins, persistence fails, or an outer transaction rolls back.
- Added a provider-free review test that denies every non-loopback request.
- Updated [[self-hosting]] and [[testing-and-ci]] with the transaction contract.
