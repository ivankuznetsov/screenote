## [2026-08-07] Align live CI gates with authoritative comparisons

**Action:** Corrected the GitGuardian incident gate to validate the Sources
API's top-level deletion flag separately from provider archive metadata. The
changed-security coverage gate now distinguishes an invalid empty overall
comparison from a real non-security change: the former still fails closed,
while the latter reports not applicable before starting the two full coverage
suites. It also compares base and current manifest membership so a manifest
edit cannot remove a guarded source from consideration. Guarded source changes
still require complete changed-line and branch coverage in both editions.

**Pages updated:** wiki/self-hosting.md, wiki/testing-and-ci.md,
wiki/log.d/20260807T113500Z-live-ci-gate-contracts.md

**Source:** `.github/workflows/secrets.yml`, `.github/workflows/release.yml`,
`bin/check_coverage`, `script/release_test_matrix`, GitGuardian's live Sources
API response, and PR #54 CI runs 31168136500 and 31168136836
