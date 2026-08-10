---
date: 2026-08-10
type: documentation
pages: [self-hosting]
---

Added a copyable README prompt that lets a coding agent complete the supported
stock-ONCE Screenote installation on a team server. The prompt asks only for
missing server access or hostname information, verifies supported hardware,
DNS, ports, and both health endpoints, and fixes recoverable setup failures.

The agent stays inside the existing public contract: the GHCR `latest` image,
an explicit matching `SCREENOTE_BASE_URL`, local screenshot storage, automatic
updates, and no optional provider configuration unless requested. It leaves
administrator credentials at the intentional human boundary and tells the
operator to claim the instance immediately after health verification. The
prompt explicitly prohibits the agent from opening or completing that claim.

Source: `README.md` and `wiki/self-hosting.md`.
