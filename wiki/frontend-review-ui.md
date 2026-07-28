---
title: Screenshot Review UI
type: ui
source: app/views/, app/javascript/controllers/annotorious_controller.js, app/assets/stylesheets/application.css
created: 2026-07-13
updated: 2026-07-13
tags: [ui, screenshots, annotations, viewports]
---

# Screenshot Review UI

TLDR: Project cards open a lone usable screenshot directly, while pages with multiple versions retain the version grid. The screenshot viewer keeps a sticky annotation sidebar beside the image, preserves scroll position when a drawing opens its comment form, and uses the Annotorious image wrapper as the coordinate box for viewport-scoped pins.

Source: `app/views/projects/show.html.erb`, `app/views/screenshots/show.html.erb`, `app/javascript/controllers/annotorious_controller.js`, `app/assets/stylesheets/application.css`

## Project-to-screenshot navigation

A page is a logical screen and a screenshot is a captured version; see [[decisions]] ADR-009 and ADR-014.

- A project page card links straight to the screenshot viewer when the page has exactly one screenshot in the active project/snapshot scope and that screenshot has an attached primary image.
- Pages with multiple versions still link to `PagesController#show`, where the user can choose a version and use page management controls.
- Empty, pending-only, failed-only, or attachment-missing pages retain the page-detail link.
- Desktop, tablet, and mobile `ScreenshotImage` children count as variants of one logical screenshot, not separate versions.
- When a project is filtered to a snapshot, the direct link targets that snapshot's selected screenshot rather than a newer ad-hoc capture.

## Long-image annotation behavior

The screenshot workspace uses the image canvas plus a sticky, independently scrollable annotation sidebar. Its top offset is relative to the viewport, so comments remain available while the document scrolls through a tall capture.

Creating an Annotorious point or rectangle prepends a comment form to the sidebar, resets only the sidebar's own scroll position so the form is visible, and focuses its textarea with `preventScroll`. This preserves the user's document position. Only one unsaved drawing is retained: starting another empty draft cancels the previous annotation, while an existing draft with typed text is preserved and the new drawing is discarded.

The canvas captures the active drawing pointer, so a rectangle remains responsive when the cursor crosses an image edge and can continue if the cursor returns before release. Geometry is normalized for either drag direction, clamped to the image endpoints, and converted from rounded percentage endpoints; fully out-of-bounds or otherwise zero-area transients are removed before another draw begins. Pointer capture and listeners are released on pointer completion, cancellation, Turbo replacement, and controller disconnect.

## Viewport image geometry

Annotorious wraps the active image in a `position: relative; display: inline-block` element. The outer canvas centers that wrapper, which centers narrow mobile images inside a desktop browser without changing wide desktop images.

Custom annotation pins are children of the same wrapper. Their percentage positions therefore resolve against the visible image dimensions rather than the wider canvas. The viewport switcher keeps annotations filtered to the layout where they were created; see [[models/screenshot-image]] and [[models/annotation]].

## Regression coverage

Controller tests cover direct-link behavior for single, multiple, empty, pending, failed, attachment-missing, snapshot-selected, and multi-viewport cases. Browser tests cover a tall screenshot without scroll jumps through draft creation and save, typed-draft preservation when a second drawing is discarded, a visible sticky form, centered mobile geometry, pin placement against the Annotorious wrapper, out-and-back boundary drags, clamping on all four edges, reverse drags, zero-area cleanup, and pointer lifecycle cleanup across Turbo replacement.

See also: [[controllers/web-controllers]], [[models/page]], [[models/screenshot]], [[models/screenshot-image]], [[models/annotation]]
