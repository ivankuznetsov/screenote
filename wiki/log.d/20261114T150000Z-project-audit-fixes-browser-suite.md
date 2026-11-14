---
timestamp: 2026-11-14T15:00:00Z
slug: project-audit-fixes-browser-suite
---

## [2026-11-14T15:00:00Z] Project audit fixes: browser suite and CI repairs

**Action:** Repaired the SaaS browser system tests that were failing on `main` and two CI jobs.

**Behaviour change:** `image_attachment_composer_controller.js#navigateAfterSubmit` now loads the workspace Turbo frame once (it used to assign `src` and call `reload()`, fetching twice) and restores the window scroll position after the frame renders. Saving a comment on a long screenshot no longer jumps the page to the top.

**Tests:** `TeamworkTest` is non-transactional because invitation services run through `DatabaseRetry`, which refuses an open transaction; stale flash, author-initial, and thumbnail-URL expectations were updated.

**CI:** New controller concerns are declared in `test/manifests/release_security_coverage.yml`; Brakeman updated to 8.1.0.

**Uncertainty:** `container-s3` cannot pull `minio/minio` (the image is no longer published on Docker Hub or Quay); a replacement image has not been chosen. `SubscriptionsFreeUserTest#test_clicking_upgrade_redirects_to_Stripe_Checkout` hangs locally with a Playwright transport error (ruby client 1.61 against driver 1.65); not run in CI.
