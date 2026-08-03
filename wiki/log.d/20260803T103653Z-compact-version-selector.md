## [2026-08-03] compact version selector

**Action:** Replaced the screenshot workspace's permanent version sidebar with a newest-first dropdown aligned to the right of the viewport switcher. The menu preserves page-scoped `version_id` links and compatible viewport state, overlays the workspace on laptops, and wraps to full width on narrow screens so more horizontal space remains available for annotations.
**Pages updated:** wiki/frontend-review-ui.md, wiki/log.md
**Source:** `app/views/pages/show.html.erb`, `app/views/screenshots/_workspace.html.erb`, `app/views/screenshots/_version_selector.html.erb`, `app/assets/stylesheets/application.css`, controller and browser regression tests
