---
date: 2026-09-25
type: correction
pages: [api-cli, commands]
---

**Action:** Corrected the CLI docs for annotation resolution.

`screenote annotation resolve` has shipped in every tagged public CLI release
since `v0.3.0` (current `v0.4.1`), so [[api-cli]] no longer says it awaits a
supported tag. Reopening is web-only by decision: the owner confirmed on
2026-09-25 that the CLI does not need a reopen command, so it is no longer
listed as deferred CLI work in [[api-cli]] or [[commands]].
