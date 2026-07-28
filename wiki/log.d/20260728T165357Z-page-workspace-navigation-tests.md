## [2026-07-28T16:53:57Z] Page workspace navigation tests

**Action:** Refreshed page-workspace navigation and screenshot-review regression coverage after the page system tests were aligned with the established workspace contract.
**Pages updated:** `wiki/frontend-review-ui.md`
**Pages verified unchanged:** `wiki/index.md`, `wiki/gaps.md`
**Source:** `test/system/pages_test.rb` on `fix/page-workspace-navigation`, plus the committed page and screenshot workspace views and controllers used by those tests.
**Notes:** The queued diff is test-only. It replaces obsolete breadcrumb traversal with browser-history or project-navigation returns, targets the `Edit page` label, and verifies that a second upload starts directly from the selected-version workspace. It changes no runtime architecture, route, API, dependency, or data-model behavior. The configured main wiki path remains unavailable; that existing uncertainty is already recorded in `wiki/gaps.md`. Did not run QMD or edit compiled `wiki/log.md`.
