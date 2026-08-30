## [2026-08-30] Run public CLI HTTP stubs through Bundler

**Action:** The retry-proxy and legacy-server subprocesses in the exact public
CLI source qualification now start with `bundle exec ruby`. GitHub Actions
installs test gems into an isolated `vendor/bundle`, so bare Ruby could not load
the declared WEBrick dependency on a clean runner.

**Pages updated:** wiki/dependencies.md,
wiki/log.d/20260830T220900Z-public-cli-bundled-stubs.md

**Source:** `script/public_cli_source_qualification`
