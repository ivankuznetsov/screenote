---
title: Testing and CI
type: operations
source: test/, bin/ci, config/ci.rb, .github/workflows/ci.yml
created: 2026-07-28
updated: 2026-07-28
tags: [testing, ci, minitest, capybara, playwright]
---

# Testing and CI

TLDR: Rails tests use Minitest, controller/model/job tests run through
`bin/rails test`, and browser regressions use Capybara with Playwright.
`bin/ci` is the complete non-browser local gate. The system suite is an
explicit separate command.

## Focused Rails tests

Use the repository bundle and serialize when exact SQL counts or shared image
fixtures matter:

```sh
BUNDLE_PATH=vendor/bundle PARALLEL_WORKERS=1 bundle exec bin/rails test \
  test/controllers/projects_controller_test.rb
```

Image-processing tests require libvips. The helper `require_vips!` skips those
tests explicitly when the system dependency is absent instead of hiding a
processing failure.

## Browser tests

System tests run the application through Capybara's in-process server and use
the Playwright driver:

```sh
BUNDLE_PATH=vendor/bundle CAPYBARA_RUN_SERVER=true PARALLEL_WORKERS=1 \
  bundle exec bin/rails test:system
```

Use the same environment for a focused system file. Serial execution keeps the
shared server, jobs, and Active Storage fixtures deterministic.

## Overview performance contracts

`ProjectsControllerTest` treats SQL shape as a regression contract:

- snapshot-filtered and unfiltered eight-page project views must use no more
  than 14 application SQL statements after caches are cleared;
- each image-bearing overview request must bulk-load tracked Active Storage
  variant records exactly once;
- adding many projects with thumbnail pages may add only a constant number of
  project-index queries;
- rendering an unwarmed named-variant URL must not create variant records or
  enqueue a job.

These tests cover request composition. Actual thumbnail transformation,
generation checks, and idempotency are covered by the screenshot thumbnail job,
model, and Rake task tests.

## Full gate

`bin/ci` installs missing dependencies and runs formatting/whitespace checks,
security scans, Rails tests, seed validation, and any configured Go tests. Set
`REQUIRE_COVERAGE=true` to enforce the SimpleCov line and branch thresholds;
coverage mode forces one Rails worker for stable accounting. System tests are
currently commented out as optional in `config/ci.rb`, so run the Playwright
command above separately when browser behavior changes.
