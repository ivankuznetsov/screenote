---
date: 2026-08-06T08:30:00Z
scope: security-testing
---

Closed three silent-pass paths in the changed-security coverage gate with an
exact discovery oracle, full branch source ranges, and ignored-untracked
detection. Browser QA then exposed and verified a retryable invitation password
mismatch: local input errors now retain the tokenless invitation context and
the collaborator email control has a persistent label. Recovery coverage also
fixed canonical IPv6 authentication-link and deployment origins and moved token
consumption ahead of password and credential mutation so a lost race rolls
back cleanly. Contradictory string/symbol provider-proof keys now fail closed by
making an explicitly present string key authoritative.

The positive manifest includes the controllers that deliver the seven guarded
flows, and `CI / coverage` is a required default-branch check rather than a
manual-only handoff command.

Final correctness review also closed two misleading retry states. Account
recovery now retains its tokenless session context and returns 503 for
retryable authority or database failures, while terminal invalid links alone
clear that context. Whole-instance backup records a successful Compose stop
before post-stop inspection so a later inspection failure accurately warns
that the service remains stopped.

The final controller pass removed local-environment throttle bypasses in favor
of configured fail-closed stores, repaired retry-state invitation rendering,
made invitation mail enqueue outcome explicit, and prevented recovery issuance
from committing a one-time link before its HTML account-list prerequisite.
Instance administration now distinguishes invalid input from unavailable
infrastructure, and unexpected mutation results fail closed with 503 retry
guidance.
