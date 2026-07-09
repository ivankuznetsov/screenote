---
timestamp: 2026-07-09T14:56:01Z
slug: local-ci-bootstrap
---

**Action:** Improved local CI bootstrap and dependency checks.

**Files changed:** `bin/ci`, `bin/setup`, `config/ci.rb`, `.github/workflows/ci.yml`, `.gitignore`, `Gemfile.lock`, `test/test_helper.rb`, `test/jobs/screenshot_dimension_job_test.rb`, `test/services/annotation_crop_service_test.rb`

**Notes:** `bin/ci` now installs missing gems before Rails boot, stores bundles in `vendor/bundle`, runs whitespace checks, keeps GitHub push CI aligned to `main`, and runs Go tests when `go.mod` is present. The lockfile was refreshed for current `bundler-audit` advisories and Brakeman freshness. GitHub CI installs `libvips` and compatible Playwright browsers for system tests; local image-processing tests skip with an explicit message when the system library is unavailable.
