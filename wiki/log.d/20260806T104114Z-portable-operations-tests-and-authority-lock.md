## [2026-08-06] Make host-operation tests portable and authority locks fail closed

**Action:** Kept production backup, restore, and diagnostics fixed at host
uid/gid 1000 while running their executable tests through an isolated,
test-only identity namespace on non-1000 CI runners. Added explicit group
validation. Rejected non-persisted authority objects before PostgreSQL row
locking so a deleted user cannot survive Rails' no-op `lock!` path.

**Pages updated:** wiki/testing-and-ci.md,
wiki/controllers/oauth-controllers.md,
wiki/log.d/20260806T104114Z-portable-operations-tests-and-authority-lock.md,
wiki/log.md
