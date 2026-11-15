---
timestamp: 2026-11-15T13:00:00Z
slug: image-native-deps-probe
---

## [2026-11-15T13:00:00Z] Probe aws-sdk-s3 and libvips in the final image

**Action:** `script/self_hosted_container_smoke` now runs `bundle exec ruby` in the built image to require `aws-sdk-s3` and `vips`, failing the `container-local` job when either cannot load. This replaces the check lost with the `container-s3` job.

**Pages updated:** `wiki/testing-and-ci.md`.

**Uncertainty:** The S3 contract tests themselves still run only through the manual `s3` gate.
