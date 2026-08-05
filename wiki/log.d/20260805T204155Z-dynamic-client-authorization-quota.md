## [2026-08-05] Bounded dynamic-client authorization

**Action:** Limited each user to 25 distinct active dynamically registered OAuth clients across authorization-code and device approval, serialized the check before credential issuance, preserved same-client reauthorization, and added deterministic global-capacity concurrency coverage.

**Decision:** A hard per-user active-client cap is safer than silently revoking a possibly active client because bearer use is not tracked precisely enough to select a trustworthy eviction candidate. Revoked credentials, expired non-refreshable credentials, expired grants, and expired device approvals stop consuming capacity; anonymous RFC 7591 registration remains idempotent and unused clients remain eligible for cleanup.

**Pages updated:** wiki/controllers/oauth-controllers.md, wiki/log.d/20260805T204155Z-dynamic-client-authorization-quota.md, wiki/log.md

**Source:** `app/services/oauth/dynamic_client_authorization_quota.rb`, `app/services/oauth/dynamic_client_registration.rb`, OAuth quota and concurrency regressions
