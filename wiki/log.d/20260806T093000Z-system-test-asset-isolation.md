## [2026-08-06] Isolate browser tests from precompiled assets

**Action:** Made the self-hosted collaboration matrix clobber ignored
precompiled assets before starting its source-backed Capybara server, preventing
a stale Propshaft manifest from shadowing current Stimulus controllers.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260806T093000Z-system-test-asset-isolation.md, wiki/log.md

**Source:** `script/release_test_matrix`, the retryable authentication-link
Playwright regression, and the observed precedence of
`public/assets/.manifest.json` over `app/javascript`
