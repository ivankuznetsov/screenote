---
title: Screenshot Review UI
type: ui
source: app/views/, app/javascript/controllers/annotorious_controller.js, app/assets/stylesheets/application.css
created: 2026-07-13
updated: 2026-07-28
tags: [ui, screenshots, annotations, viewports]
---

# Screenshot Review UI

TLDR: Project cards open the canonical page workspace at a selected version and emit thumbnails only after asynchronous warming completes. The workspace keeps version history beside the review canvas, keeps a sticky annotation sidebar beside the image, preserves scroll position when a drawing opens its comment form, and uses the Annotorious image wrapper as the coordinate box for viewport-scoped pins.

Source: `app/controllers/concerns/page_workspace_navigation.rb`, `app/controllers/pages_controller.rb`, `app/controllers/screenshots_controller.rb`, `app/models/screenshot_image.rb`, `app/jobs/screenshot_thumbnail_job.rb`, `app/views/projects/index.html.erb`, `app/views/projects/show.html.erb`, `app/views/pages/show.html.erb`, `app/views/screenshots/_workspace.html.erb`, `app/javascript/controllers/annotorious_controller.js`, `app/assets/stylesheets/application.css`, `test/controllers/projects_controller_test.rb`, `test/system/pages_test.rb`, `test/system/annotations_test.rb`, `test/system/api_upload_test.rb`

## Project-to-workspace navigation

A page is a logical screen and a screenshot is a captured version; see [[decisions]] ADR-009 and ADR-014.

- Project page cards with a selected thumbnail use the shared `page_workspace_path_for` helper to link to `PagesController#show`, the canonical review workspace. The helper builds the page route from `screenshot.page_id` and encodes the screenshot id as the page-scoped `version_id`; cards without a selected screenshot retain the bare page route.
- The workspace opens that version directly and keeps newest-first version history in a text sidebar instead of requiring a thumbnail-grid detour.
- Empty, pending-only, failed-only, or attachment-missing pages retain the bare page route and management state.
- Desktop, tablet, and mobile `ScreenshotImage` children count as variants of one logical screenshot, not separate versions.
- When a project is filtered to a snapshot, the page-workspace link targets that snapshot's selected screenshot rather than a newer ad-hoc capture.

Legacy screenshot and viewport URLs redirect to the same page workspace. The redirect forwards a viewport only when that screenshot actually has the requested variant, and forwards an annotation status only when it is a key in the current `Annotation.statuses` enum. `PagesController#show` applies the same enum-backed status check before filtering the active viewport's annotations.

The page breadcrumb intentionally links only to the page's canonical URL; it is not a project back link. A direct project-to-page visit can return through browser history, while flows that need a fresh overview use project navigation. Page management uses the explicit `Edit page` action. A successful version upload returns directly to that page's workspace with the uploaded version selected, so another upload can start without a breadcrumb round trip.

## Overview thumbnail delivery

Project and page overviews emit Active Storage representation URLs only after
all three named thumbnail variants are present in the current blob's preloaded
tracked variant records. This keeps browser image requests from processing an
unwarmed variant synchronously. A page with a selected screenshot but unfinished
thumbnail warming keeps its version-specific workspace link and shows
`Thumbnail processing`; a project strip simply omits that image. Overview GETs
neither process variants nor enqueue thumbnail jobs.

## Long-image annotation behavior

The screenshot workspace uses the image canvas plus a sticky, independently scrollable annotation sidebar. Its top offset is relative to the viewport, so comments remain available while the document scrolls through a tall capture.

Creating an Annotorious point or rectangle prepends a comment form to the sidebar, resets only the sidebar's own scroll position so the form is visible, and focuses its textarea with `preventScroll`. This preserves the user's document position. Only one unsaved drawing is retained: starting another empty draft cancels the previous annotation, while an existing draft with typed text is preserved and the new drawing is discarded.

## Viewport image geometry

Annotorious wraps the active image in a `position: relative; display: inline-block` element. The outer canvas centers that wrapper, which centers narrow mobile images inside a desktop browser without changing wide desktop images.

Custom annotation pins are children of the same wrapper. Their percentage positions therefore resolve against the visible image dimensions rather than the wider canvas. The viewport switcher keeps annotations filtered to the layout where they were created; see [[models/screenshot-image]] and [[models/annotation]].

Annotation create and update accept a nonblank viewport only when that viewport
exists on the selected screenshot. Blank viewport input is ignored, preserving
the desktop model default on create and the stored viewport on update.

## Regression coverage

Controller tests cover page-workspace links for single, multiple, empty, pending, failed, attachment-missing, snapshot-selected, and multi-viewport cases. They also verify that unwarmed page cards and project strips contain no representation URLs, process no variants, and enqueue no jobs. The page system suite treats the page breadcrumb as a canonical page self-link rather than project navigation: it uses browser history or explicit project navigation to return to the project overview, targets the `Edit page` label, and starts a second upload directly from the selected-version workspace reached after the first upload. The API upload system test also verifies that clicking the uploaded page card lands in the screenshot workspace rather than an intermediate version-card view. Browser annotation tests cover a tall screenshot without scroll jumps through draft creation and save, typed-draft preservation when a second drawing is discarded, a visible sticky form, centered mobile geometry, and pin placement against the Annotorious wrapper.

See also: [[controllers/web-controllers]], [[models/page]], [[models/screenshot]], [[models/screenshot-image]], [[models/annotation]]
