## [2026-08-03] fullscreen screenshot review

**Action:** Added an accessible fullscreen review mode that fits the active screenshot to the browser viewport without changing its aspect ratio, floats the annotation sidebar above the image, preserves Annotorious coordinate alignment and fullscreen state across annotation Turbo updates, and exits through either Escape or a visible X control.
**Pages updated:** wiki/frontend-review-ui.md, wiki/log.md
**Source:** `app/views/screenshots/_workspace.html.erb`, `app/javascript/controllers/review_fullscreen_controller.js`, `app/javascript/controllers/annotorious_controller.js`, `app/assets/stylesheets/application.css`, `test/system/annotations_test.rb`
