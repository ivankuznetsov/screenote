---
date: 2026-08-06T06:45:00Z
scope: testing-and-ci
---

Repaired the source-release coverage gate so it measures the contract it names. Coverage now starts before Rails boot, uses independent SaaS and explicit self-hosted processes, and applies a positive seven-domain source manifest to executable lines and branch arms changed from the trusted `origin/main` merge base. The changed security surface remains fixed at 100%; the legacy whole-application `MIN_COVERAGE` behavior is not used to weaken the release gate.
