---
title: Screenshot Review UI
type: ui
source: app/views/, app/javascript/controllers/annotorious_controller.js, app/assets/stylesheets/application.css
created: 2026-07-13
updated: 2026-08-03
tags: [ui, screenshots, annotations, viewports]
---

# Screenshot Review UI

TLDR: Project cards open the canonical page workspace at a selected version,
with newest-first history in a compact dropdown beside the viewport switcher.
The viewer keeps a sticky annotation sidebar beside a practical-width image
canvas, can expand the screenshot into a viewport-fitted review surface with
floating comments, preserves scroll position when a drawing opens its comment
form, and uses the Annotorious image wrapper as the coordinate box for
viewport-scoped pins.

Source: `app/views/projects/show.html.erb`, `app/views/pages/show.html.erb`,
`app/views/screenshots/_workspace.html.erb`,
`app/javascript/controllers/annotorious_controller.js`,
`app/javascript/controllers/review_fullscreen_controller.js`,
`app/assets/stylesheets/application.css`

## Project-to-screenshot navigation

A page is a logical screen and a screenshot is a captured version; see [[decisions]] ADR-009 and ADR-014.

- Every project page card links to `PagesController#show`, the canonical review
  workspace. When a ready version is selected, its id is encoded as the
  page-scoped `version_id`.
- The workspace opens that version immediately and keeps newest-first history
  as real links in a dropdown aligned to the right of the viewport switcher; it
  never renders a thumbnail grid before review. The menu overlays the workspace
  instead of reserving a permanent column, and becomes full-width below 760px.
- Empty, pending-only, failed-only, or attachment-missing pages retain the bare
  page route and management state.
- Page and version actions in the workspace header use the same rendered height
  and width; color still distinguishes primary, secondary, and destructive actions.
- Desktop, tablet, and mobile `ScreenshotImage` children count as variants of one logical screenshot, not separate versions.
- When a project is filtered to a snapshot, the page-workspace link targets
  that snapshot's selected screenshot rather than a newer ad-hoc capture.

## Overview image delivery

Project-strip thumbnails use a prewarmed 240x160 named variant rendered at
120x80. Page cards use prewarmed 480x270 and 960x540 named variants with a
responsive `srcset` and grid-aware `sizes`. Overview requests only construct
representation URLs: they neither process images nor enqueue jobs. Nested
preloads keep page cards, snapshot cards, and project strips at constant query
cost as their counts grow.

## Long-image annotation behavior

The screenshot workspace uses the image canvas plus a sticky, independently scrollable annotation sidebar. Its top offset is relative to the viewport, so comments remain available while the document scrolls through a tall capture.

Creating an Annotorious point or rectangle prepends a comment form to the sidebar, resets only the sidebar's own scroll position so the form is visible, and focuses its textarea with `preventScroll`. This preserves the user's document position. Only one unsaved drawing is retained: starting another empty draft cancels the previous annotation, while an existing draft with typed text is preserved and the new drawing is discarded.

The canvas captures the active drawing pointer, so a rectangle remains responsive when the cursor crosses an image edge and can continue if the cursor returns before release. Geometry is normalized for either drag direction, clamped to the image endpoints, and converted from rounded percentage endpoints; fully out-of-bounds or otherwise zero-area transients are removed before another draw begins. Pointer capture and listeners are released on pointer completion, cancellation, Turbo replacement, and controller disconnect.

## Viewport image geometry

Annotorious wraps the active image in a `position: relative; display: inline-block` element. The outer canvas centers that wrapper, which centers narrow mobile images inside a desktop browser without changing wide desktop images.

Custom annotation pins are children of the same wrapper. Their percentage positions therefore resolve against the visible image dimensions rather than the wider canvas. The viewport switcher keeps annotations filtered to the layout where they were created; see [[models/screenshot-image]] and [[models/annotation]].

Review pages opt into an 1800px main-content ceiling instead of the global
960px reading width. Removing the permanent version column leaves at least
800px for the annotation canvas at the standard 1280px browser-test viewport;
wider displays can show desktop captures close to their natural size. Desktop,
tablet, and mobile switcher segments use one fixed rendered width so changing
the active viewport does not resize the control. The version selector shares
that toolbar row on laptops and wraps above the canvas on narrow screens.

## Fullscreen review

The screenshot canvas has an icon button in its top-right corner that expands
the workspace over the full browser viewport. The active image is fitted to
the viewport while preserving its natural aspect ratio, and the Annotorious
wrapper receives the same fitted dimensions so drawings and pins keep the
image as their coordinate boundary. The annotation sidebar floats over the
right side of the canvas and remains independently scrollable.

Fullscreen review locks document scrolling and exits through the visible X
button or the Escape key. Turbo frame replacements preserve the body-level
fullscreen intent, and the replacement controller restores the workspace and
global listeners so saving or filtering annotations does not collapse the
review surface. Explicit exit removes the body class, event listeners, and
image-fit modifier classes.

## Regression coverage

Controller tests cover page-workspace links for single, multiple, empty,
pending, failed, attachment-missing, snapshot-selected, and multi-viewport
cases; responsive variant markup; request-time processing absence; and bounded
SQL for filtered, unfiltered, and growing project lists. Browser tests cover a
tall screenshot without scroll jumps through draft creation and save, typed
draft preservation when a second drawing is discarded, a visible sticky form,
centered mobile geometry, pin placement against the Annotorious wrapper,
out-and-back boundary drags, clamping on all four edges, reverse drags,
zero-area cleanup, and pointer lifecycle cleanup across Turbo replacement.
They also enforce a practical desktop canvas width and equal rendered
dimensions for the page actions and viewport-switcher segments, plus the
version selector's toolbar placement, newest-first link order, version
navigation, and narrow-screen wrapping and menu bounds.
Fullscreen browser coverage verifies viewport-sized canvas geometry,
aspect-ratio-preserving image fit across resize, floating comment bounds,
annotation creation across Turbo replacement, restored Escape handling,
scroll-lock cleanup, and X-button exit.

See also: [[controllers/web-controllers]], [[models/page]], [[models/screenshot]], [[models/screenshot-image]], [[models/annotation]]
