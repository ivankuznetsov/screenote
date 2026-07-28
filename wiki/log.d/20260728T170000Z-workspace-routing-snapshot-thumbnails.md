## [2026-07-28T17:00:00Z] Workspace routing and snapshot thumbnail selection

**Action:** Refreshed the page-workspace and snapshot documentation after project cards adopted the shared workspace-route helper, legacy screenshot redirects tied status validation to the Annotation enum, and snapshot thumbnail selection moved from Ruby-side de-duplication to a deterministic SQL selection.
**Pages updated:** `wiki/frontend-review-ui.md`, `wiki/controllers/web-controllers.md`, `wiki/models/snapshot.md`, `wiki/gaps.md`
**Pages verified unchanged:** `wiki/index.md`, `wiki/routes.md`, `wiki/data-model.md`, `wiki/dependencies.md`
**Behavior:** A project card with a selected screenshot routes to `/pages/:page_id?version_id=:screenshot_id`; cards without a selected version retain the bare page route. Legacy screenshot and viewport URLs redirect to that workspace, forwarding only screenshot-backed viewports and enum-backed annotation statuses.
**Selection:** `Snapshot#thumbnails_for` now uses a correlated anti-existence query to return only the newest ready screenshot for each requested page, with `id` as the tie-break when timestamps match, while preserving the viewport-image preload used by project cards.
**Source:** commit `206ee512a5cb7b671e45e7ac721e120cb1f73f27`; `app/controllers/concerns/page_workspace_navigation.rb`, `app/controllers/pages_controller.rb`, `app/controllers/screenshots_controller.rb`, `app/models/snapshot.rb`, `app/views/projects/show.html.erb`, `test/models/snapshot_test.rb`, and `test/system/api_upload_test.rb` read with `git show`.
**Uncertainty:** The configured main wiki path `/home/asterio/wikis/master/wiki` remains unavailable, so cross-project context could not be searched; the ongoing gap is recorded in `wiki/gaps.md`.
**Notes:** Updated only files under `wiki/`. Did not run QMD or edit compiled `wiki/log.md`.
