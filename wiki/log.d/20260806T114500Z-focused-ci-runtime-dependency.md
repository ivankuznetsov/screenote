## [2026-08-06] Keep focused Rails CI jobs runtime-complete

**Action:** Added libvips installation to the focused backup/restore CI job and
a workflow contract that requires the package before Rails setup. Documented
that the Vips initializer makes the native runtime a boot dependency even for
focused tests that do not directly transform images.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260806T114500Z-focused-ci-runtime-dependency.md, wiki/log.md

**Source:** .github/workflows/ci.yml, the backup/restore CI failure, and the
release artifact workflow contract
