## [2026-08-03] fullscreen comment controls

**Action:** Replaced the fullscreen X with a restore-size control and added an accessible comments icon that collapses and reopens the floating annotation sidebar. The sidebar remains open by default, its visibility survives Turbo frame updates while fullscreen, beginning an annotation reopens it before the comment form appears, and a later fullscreen entry resets it to open.
**Pages updated:** wiki/frontend-review-ui.md
**Source:** `app/views/screenshots/_workspace.html.erb`, `app/javascript/controllers/annotorious_controller.js`, `app/javascript/controllers/review_fullscreen_controller.js`, `app/assets/stylesheets/application.css`, `test/system/annotations_test.rb`
