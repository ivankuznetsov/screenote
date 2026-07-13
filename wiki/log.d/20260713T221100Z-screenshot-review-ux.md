## [2026-07-13T22:11:00Z] Screenshot review navigation and geometry

**Action:** Documented the project-card shortcut for a lone usable screenshot, sticky long-image annotation behavior, sidebar-local form scrolling with scroll-preserving comment focus, and Annotorious wrapper-based mobile centering and pin coordinates.
**Pages added:** wiki/frontend-review-ui.md
**Pages updated:** wiki/index.md, wiki/gaps.md, wiki/controllers/web-controllers.md
**Decision:** Responsive images remain variants of one logical screenshot. Review navigation skips the version grid only when exactly one usable logical screenshot exists, and all percentage annotation geometry is resolved against the visible image wrapper rather than the wider canvas.
**Source:** app/views/projects/show.html.erb, app/javascript/controllers/annotorious_controller.js, app/assets/stylesheets/application.css, regression tests in test/controllers/projects_controller_test.rb and test/system/annotations_test.rb
