## [2026-08-29] Remove the PostgreSQL qualification fixture password

**Action:** Changed the runner-local PostgreSQL service used by the attachment
concurrency qualification workflow to trust authentication and a
credential-free loopback URL. This preserves the isolated CI database while
keeping password-shaped fixture bytes out of the published diff.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260829T034017Z-postgres-ci-auth.md

**Source:** `.github/workflows/concurrency-qualification.yml`
