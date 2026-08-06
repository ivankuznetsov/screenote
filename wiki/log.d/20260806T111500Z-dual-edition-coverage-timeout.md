## [2026-08-06] Budget dual-edition coverage for both complete suites

**Action:** Raised the required PR coverage job timeout from 25 to 45 minutes
and added a workflow contract that prevents the dual-edition gate from being
compressed below that budget. The first complete SaaS suite can consume about
18 minutes on a hosted runner before the self-hosted suite and merged changed
line/branch analysis begin.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260806T111500Z-dual-edition-coverage-timeout.md, wiki/log.md

**Source:** .github/workflows/ci.yml, CI run 31094471802, and
test/integration/release_artifact_contract_test.rb
