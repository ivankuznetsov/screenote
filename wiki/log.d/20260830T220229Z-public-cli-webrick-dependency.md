## [2026-08-30] Declare the public CLI qualification HTTP server

**Action:** Added WEBrick as a test-only dependency because the exact public
CLI source qualification starts isolated retry-proxy and legacy-server HTTP
stubs. Clean Ruby installations no longer depend on an untracked global gem to
run the Disk and MinIO source-contract gates.

**Pages updated:** wiki/dependencies.md,
wiki/log.d/20260830T220229Z-public-cli-webrick-dependency.md

**Source:** `Gemfile`, `Gemfile.lock`,
`script/public_cli_source_qualification`
