---
date: 2026-08-09
type: bugfix
pages: [self-hosting, architecture, gaps]
---

Qualified the current working tree through a real local ONCE v0.3.0 lifecycle:
claim, browser upload, restart reconciliation, exact-image replacement, local
backup, destructive restore, and persistence of all four SQLite roles, blobs,
variants, annotations, replies, cache, queue, and cable state.

The HTTP/VPN proxy probe found that ONCE and Thruster both preserved incoming
forwarding headers. The image also assumed a 172.16/12 Docker proxy range while
ONCE allocated 192.168.192.0/20, collapsing Rails client identity onto the
proxy; a supplied X-Forwarded-Proto value changed generated redirect schemes.

Replaced subnet-based inference with an explicit named-proxy contract. The ONCE
and hosted Kamal profiles promote the forwarded client only when the final hop
matches the current proxy identity from a bounded DNS lookup; the identity is
refreshed through a short synchronized cache so anonymous requests cannot fan
out DNS work. A failed refresh publishes an empty identity instead of retaining
stale authority. A sibling that bypasses that proxy, or a request whose refresh
fails, is attributed to its own final hop. Direct-container qualification uses
one hop, all forwarded headers are then removed, and the canonical base URL
supplies the scheme. Real hostile-header and same-network sibling probes after
image replacement kept the actual client address and configured scheme.
A live proxy address rotation with the application left running also retained
the client address, then restored the original proxy topology cleanly.
The final public candidate still requires retained HTTPS and exact-artifact
qualification. ONCE's mutable `basecamp/kamal-proxy:once-01` tag also means
release evidence must retain the proxy digest actually exercised.

The hosted Cloudflare path still records the Cloudflare edge as the client,
matching its predecessor behavior. Correct browser attribution there needs a
separate authenticated Cloudflare-origin contract or a DNS-only origin; it is
tracked as an unresolved hosted deployment gap rather than being approximated
with another unauthenticated forwarded header.

Source: `lib/screenote/trusted_proxy_headers.rb`,
`lib/screenote/deployment.rb`, `Dockerfile`, `compose.yaml`,
`config/deploy.saas.yml`, `docs/once-deployment.md`, and the local ONCE v0.3.0
runtime drill.
