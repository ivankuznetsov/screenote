---
date: 2026-08-06T06:15:00Z
scope: self-hosting
---

The `system-collaboration` release matrix now owns a fixed test-only bootstrap token for its unclaimed-installation browser test and explicitly removes the token for claimed-installation tests. This makes the standalone matrix deterministic and preserves coverage of both bootstrap-required and post-claim operation. The self-hosted positive manifest also includes the instance-administration controller suite explicitly, so those routes cannot silently skip under the SaaS coverage process.
