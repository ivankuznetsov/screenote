## [2026-08-06] Keep focused Rails CI jobs runtime-complete

**Action:** Added libvips installation to every focused CI job that boots Rails
and a workflow contract that requires the package before Ruby setup. Routed
Playwright version discovery through the bundle and disabled Bootsnap's compile
cache in coverage processes. Documented that native and bundled runtimes remain
boot dependencies even when a focused test does not directly use them.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260806T114500Z-focused-ci-runtime-dependency.md, wiki/log.md

**Source:** .github/workflows/ci.yml, the backup/restore CI failure, and the
release artifact workflow contract
