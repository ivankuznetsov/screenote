## [2026-08-07] Harden retained load qualification evidence

**Action:** Review-hardened the tracked minimum-host qualification. The driver
now measures capacity on its exact Docker storage volume, bounds and reaps
Docker subprocess groups, claims deterministic names for cleanup before Docker
creation completes, allows both bounded cleanup operations to finish on
termination, and exercises its lifecycle through a deterministic command harness. The incompatible structured evidence
contract is versioned as `screenote-load-smoke/v2`, and the qualification
artifact retains and hashes the validated numeric measurements. Coverage-gate
documentation now shows the required event comparison SHA for local runs.

**Pages updated:** wiki/self-hosting.md, wiki/testing-and-ci.md,
wiki/log.d/20260807T101500Z-load-qualification-hardening.md, wiki/log.md

**Source:** script/self_hosted_load_driver, script/self_hosted_load_smoke,
.github/workflows/release-qualification.yml, .github/workflows/release.yml,
and focused integration contracts
