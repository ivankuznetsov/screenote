## [2026-08-06] Keep non-interactive Compose execution portable

**Action:** Replaced the version-sensitive long Compose exec TTY flag with
portable `-T` in the final-image processing poll, restored-instance
verification, and operator diagnostics. Added source contracts for every path
after hosted Compose 2.38.2 rejected the lowercase long spelling while the
application itself remained healthy.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260806T101326Z-compose-exec-portability.md, wiki/log.md
