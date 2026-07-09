---
timestamp: 2026-07-09T14:56:01Z
slug: local-ci-bootstrap
---

**Action:** Improved local CI bootstrap and dependency checks.

**Files changed:** `bin/ci`, `bin/setup`, `bin/check_coverage`, `config/ci.rb`, `.github/workflows/ci.yml`, `.gitignore`, `Gemfile.lock`, `test/test_helper.rb`, `test/jobs/screenshot_dimension_job_test.rb`, `test/services/annotation_crop_service_test.rb`

**Notes:** `bin/ci` now installs missing gems before Rails boot, stores bundles in `vendor/bundle`, runs whitespace checks, keeps GitHub push CI aligned to `main`, and runs Go tests when `go.mod` is present. Set `REQUIRE_COVERAGE=true` to run Rails tests with SimpleCov and fail below 100% line or branch coverage via `bin/check_coverage`; coverage runs force one worker for stable measurement, and `PARALLEL_WORKERS` can override normal Rails test parallelism. The lockfile was refreshed for current `bundler-audit` advisories, Brakeman freshness, and Playwright protocol compatibility. GitHub CI installs `libvips` and compatible Playwright browsers for system tests, runs Capybara against its in-process Rails server when `CAPYBARA_RUN_SERVER=true`, serializes system tests with `PARALLEL_WORKERS=1`, and caps the system-test job at 15 minutes. System fixtures now include the seed-equivalent `test@screenote.app`, `free@screenote.app`, and `Demo Project` records expected by browser tests. Browser API/MCP helpers derive the live Capybara server URL, invitation tests inspect test mail deliveries instead of letter_opener files, and mailer preview assertions live in mailer tests; local image-processing tests skip with an explicit message when the system library is unavailable.
