## [2026-08-07] Track minimum-host load qualification

**Action:** Added the versioned Linux AMD64 minimum-host profile and a tracked
release-only driver that constrains the exact candidate to 2 vCPUs and 4 GiB
RAM, runs 25 authenticated API sessions, overlaps four exact 20 MiB uploads,
schedules 20 uniquely identified comment mutations per second for ten minutes,
and reports latency, reconciliation, queue-drain, lock, integrity, and request
evidence. Qualification now hashes the profile bytes from the exact source
commit rather than trusting opaque repository-variable text. The live runner
and exact retained qualification result remain publication blockers.

**Pages updated:** wiki/self-hosting.md, wiki/gaps.md,
wiki/log.d/20260807T083000Z-minimum-host-load-qualification.md, wiki/log.md

**Source:** config/release/minimum-host-v1.json,
script/self_hosted_load_driver, script/self_hosted_load_smoke,
.github/workflows/release-qualification.yml, and focused integration contracts
