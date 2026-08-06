## [2026-08-06] Prove concurrency overlap and cross-session outcomes

**Action:** Replaced simultaneous-start race tests with deterministic barriers
that prove a competing database connection blocks while the first operation
holds its critical lock. Expanded the required self-hosted browser gate so the
original collaborator reads another member's reply, suspended sessions lose
access, restored accounts require a new sign-in, and recovery links reset
credentials once while rejecting replay.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260806T110000Z-deterministic-concurrency-browser-outcomes.md,
wiki/log.md

**Source:** deterministic concurrency integration tests and self-hosted
collaboration/instance-administration system tests
