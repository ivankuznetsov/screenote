## [2026-07-28T17:34:28Z] Responsive thumbnail system proof

**Action:** Added testing and CI coverage after the page system suite gained explicit browser pixel-ratio configuration and end-to-end responsive-image selection proof.
**Pages added:** `wiki/testing-and-ci.md`
**Pages updated:** `wiki/index.md`, `wiki/gaps.md`
**Behavior:** `DEVICE_SCALE_FACTOR` configures the Playwright context. The page-card system test warms the uploaded screenshot's thumbnail variants, checks the browser-reported device pixel ratio, proves `currentSrc` selects the 480w candidate at 1x and the 960w candidate at 2x, and confirms that selected representation was requested. The shared page-object assertion now waits for the warmed thumbnail image rather than merely checking that its card is visible.
**Source:** commit `d09376aac55f19ed951b4a03cca0a5e5e284cd3f`; `test/system/application_system_test_case.rb`, `test/system/pages/pages_page.rb`, `test/system/pages_test.rb`, and the commit's `wiki/testing-and-ci.md` read with `git show`.
**Uncertainty:** The configured main wiki path `/home/asterio/wikis/master/wiki` remains unavailable, so cross-project context could not be searched; the ongoing gap remains recorded in `wiki/gaps.md`.
**Notes:** The queued source diff changes test configuration, assertions, and wiki documentation only; it does not change runtime architecture, routes, APIs, dependencies, or the data model. Updated only files under `wiki/`. Did not run QMD or edit compiled `wiki/log.md`.
