---
date: 2026-08-09
type: fix
pages: [self-hosting, gaps]
---

Made the hosted Kamal readiness window explicit and bounded at fifteen minutes.
The hosted profile previously inherited Kamal 2.10.1's 30-second default while
the container entrypoint synchronously reconciled durable screenshot work
before starting Thruster. A production corpus of 371 legacy screenshot images
kept making successful progress for several minutes, so Kamal terminated a
healthy successor before it could expose readiness. The configuration contract
now prevents the SaaS profile from silently returning to the framework default.
