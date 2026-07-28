---
title: Guard overview representation URLs until thumbnail warming completes
date: 2026-07-28
---

Project cards and strips now consult the preloaded tracked variant records before
emitting named Active Storage representation URLs. Unwarmed page cards show a
thumbnail-processing placeholder and project strips omit their image, preserving
asynchronous `ScreenshotThumbnailJob` warming instead of allowing browser image
requests to process variants synchronously.

Thumbnail processing failures now retry up to three times, and retries skip
already tracked variants so partial generations resume without duplicate work.

Annotation writes also reject enum-valid viewports that the selected screenshot
does not have, preventing records hidden from every reachable workspace.

Playwright can now run at explicit 1x and 2x device scale factors; the page-card
system test proves the browser selects and requests the 480w and 960w candidates.
