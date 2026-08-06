---
date: 2026-08-06T07:15:00Z
scope: testing-and-ci
---

Corrected the final-image dependency probe to run through the image's Bundler
environment. A real ARM64 build, self-hosted preflight, Rails boot, and gem load
proved the packaged S3 and libvips runtimes were present; the previous bare Ruby
probe bypassed `BUNDLE_PATH` and produced a false missing-gem failure. The same
Bundler-aware command was reproduced successfully against the AMD64 image.
