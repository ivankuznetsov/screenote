# Publication checklist

This checklist summarizes the technical setup and exact-artifact checks around the automated release workflow.

## Repository protection and security scans

- [ ] GitGuardian GitHub App installed on the repository and its historical scan finished.
- [ ] Exact GitGuardian App check source/name required by the main ruleset; skip actions disabled.
- [ ] Full-history and current-tree `ggshield` scans passed for the candidate SHA.
- [ ] Every incident page was queried and no `TRIGGERED` or `ASSIGNED` incident remains.
- [ ] Main ruleset blocks direct/force pushes and deletion and requires every product/security check.
- [ ] `v*` creation is limited to the release App; update, force-push, and deletion are blocked for everyone.
- [ ] `source-release` environment, least-privilege Actions settings, GHCR access, immutable releases, and private vulnerability reporting are configured.

## Exact artifacts and compatibility

- [ ] AMD64 and ARM64 OCI layouts were built once from the protected default-branch SHA.
- [ ] Imported config/layer digests match the retained layouts.
- [ ] Exact platform images passed GitGuardian and pinned Critical/High vulnerability policy.
- [ ] Manifest labels, platform digests, SBOM, provenance, and public-log sentinel checks passed.
- [ ] The exact `tag@digest` image passed its retained Linux deployment
  through the supported ONCE stable release named in the evidence. It used the
  native `curl https://get.once.com/screenote | sh` alias plus its
  `ONCE_HOST`/`DISABLE_SSL` contract, ONCE's Kamal Proxy, and Thruster, with
  automatic application updates enabled. Evidence includes the tokenless
  first-visitor administrator claim, exact proxy manifest digest, HTTPS,
  normal forwarding, hostile-header and direct-sibling spoof rejection,
  restart, volume persistence, and a bare `once update HOST`.
- [ ] Published ONCE backup/restore commands recovered all four SQLite roles
  and local screenshot files with the exact image; S3 mode also recovered the
  matching external object namespace.
- [ ] A successor candidate upgraded and restored every earlier published
  release directly to the candidate through the moving release channel.
- [ ] Protected-main jobs are recorded only as `pr_contract_only` source checks.
- [ ] Exact qualification booted the retained AMD64 and ARM64 candidate in
  self-hosted and SaaS modes; both SaaS boots exercised four URL-driven
  database roles through Active Record without an adapter/version assertion.
- [ ] Exact qualification passed same-image backup/restore and the minimum-host SQLite load profile.
- [ ] The immutable public CLI tag passed HTTP and proxied-HTTPS checks against candidate-backed origins.
- [ ] Qualification run/attempt, five jobs, artifact ID/archive digest, record bytes, and eight check hashes were verified live.
- [ ] Release notes name the immediate predecessor, all supported upgrade
  sources, image digest, CLI tag,
  data/configuration changes, irreversible migrations, maintenance procedure,
  verified backup/restore boundary, and resumable migration checks; they do
  not promise one transaction can roll back an entire migration chain.

## Promotion

- [ ] `docs/releases/PUBLICATION_BLOCKED.md` was removed after every technical prerequisite above became available.
- [ ] The v2 public evidence manifest contains only technical fields and matches the exact candidate and qualification artifacts.
- [ ] `bin/release-validate --mode publish` passed for the exact tag, source SHA, and qualification artifact.
- [ ] A reviewer approved the current workflow run's protected `source-release` environment.
- [ ] Existing image/tag/attestation/release objects were absent or an exact resumable prefix.
- [ ] The immutable release body and exact technical assets, image manifest, source tag, and provenance attestation were verified after publication.
- [ ] The public `latest` channel resolves to the newest release's exact image manifest.
