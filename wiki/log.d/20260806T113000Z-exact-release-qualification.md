## [2026-08-06] Separate source contracts from exact release qualification

**Action:** Added a dedicated fail-closed release-qualification workflow and
made promotion live-verify its exact run, job set, retained artifact bytes,
candidate identities, and immutable CLI tag. Pull-request results are now
explicitly source-contract evidence only. SaaS qualification boots the exact
candidate through its production entrypoint against pinned PostgreSQL 16, and
the public CLI driver must return independently validated HTTP and HTTPS
evidence with strict origin, candidate, CLI, and TLS bindings. Documented the
native runner, minimum-host, tracked driver, candidate-origin, and CLI-tag
prerequisites that still block publication.

**Pages updated:** wiki/self-hosting.md, wiki/testing-and-ci.md, wiki/gaps.md,
wiki/log.d/20260806T113000Z-exact-release-qualification.md, wiki/log.md

**Source:** .github/workflows/release-qualification.yml,
.github/workflows/release.yml, bin/release-validate, and release artifact
contract tests
