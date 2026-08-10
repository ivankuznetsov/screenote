---
date: 2026-08-09
type: decision
pages: [self-hosting, decisions, architecture, gaps, data-model, schema-evolution]
---

Replaced Screenote's custom first-boot ONCE configuration with a native
one-command install: `curl https://get.once.com/screenote | sh`. ONCE prompts
for the hostname, injects `ONCE_HOST` plus `DISABLE_SSL` when appropriate, and
enables automatic updates. Screenote derives its canonical origin from those
host/TLS settings; an explicit `SCREENOTE_BASE_URL` remains only as an advanced
matching override.

Removed the administrator bootstrap credential from the current runtime and
documented the transactional first-visitor claim. New unclaimed Installation
rows carry no secret, one concurrent setup submission records the sole
administrator, and later account creation remains invitation-only. The
obsolete nullable digest column stays for one compatibility release so
predecessor-created rows remain readable during rollout; the new claim path
clears any legacy value.

The public operator path now leads with the native installer and a bare
`once update HOST` for an immediate update. Advanced direct deployment remains
available for HTTP-only VPN operation or choosing S3 before the first boot.
Exact-image qualification, backup/restore evidence, and the upstream ONCE
catalog/host-injection release remain publication dependencies.

Source: `lib/screenote/deployment.rb`, `app/services/installations/claim.rb`,
`app/services/installations/prepare.rb`,
`db/migrate/20260809120000_allow_tokenless_installation_bootstrap.rb`,
`README.md`, `docs/once-deployment.md`, and `docs/self-hosting.md`.
