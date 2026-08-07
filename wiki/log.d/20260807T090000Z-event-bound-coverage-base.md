## [2026-08-07] Bind coverage to the event comparison commit

**Action:** Replaced the coverage gate's runtime `origin/main` merge-base
lookup with an exact event-bound comparison SHA: the pull-request base commit
for pull requests and the previous default-branch tip for pushes. The matrix
validates that the supplied value is a full available ancestor before running
both edition suites, preventing a push checkout from comparing `HEAD` with
itself and failing only after the full test run.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260807T090000Z-event-bound-coverage-base.md, wiki/log.md

**Source:** .github/workflows/ci.yml, script/release_test_matrix,
test/integration/release_artifact_contract_test.rb, and CI run 31155056854
