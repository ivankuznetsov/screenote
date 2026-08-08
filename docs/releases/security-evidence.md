# Technical release evidence

Release evidence binds one exact source commit to the exact image, scans, qualification run, and published artifacts.

## Public evidence

The v2 manifest contains only technical release state:

- repository and exact source SHA;
- release tag, predecessor, immutable CLI tag, and release-note hash;
- exact AMD64, ARM64, and manifest digests;
- OCI labels, SBOM, provenance, and retained candidate hashes;
- GitGuardian App/source/incident/image status, versions, counts, timestamps, and report hashes;
- Trivy policy/version, exact-image counts, and tightly scoped expiring waivers;
- canonical live ruleset hashes and expected GitHub App identities;
- protected-main CI conclusions labelled `pr_contract_only`;
- exact qualification workflow run/attempt, artifact and record hashes,
  platform/CLI identities, minimum-host profile, adapter-neutral SaaS boot
  identities, and eight check hashes; and
- public-log and release-asset hashes.

Use [`evidence/public-evidence.example.json`](evidence/public-evidence.example.json) as the template. `bin/release-validate` rejects unknown fields, placeholders, malformed hashes, open incidents, unwaived Critical/High findings, expired waivers, stale checks, mismatched source or artifact identities, and prohibited secret/path content.

The exact O'Saasy license and Future Spin Ltd copyright notice are checked directly from the release tree by `bin/release-validate --mode prepare`.

## Exact artifact binding

`artifacts.evidence_sha256` is the SHA-256 of `screenote-candidate.tar`; `sbom_sha256` identifies its canonical two-platform SBOM set; and `provenance_sha256` identifies its retained provenance input. Publication downloads the named candidate artifact from the exact successful workflow run and verifies all three before mutation.

`source_contracts` records protected-main CI only. `qualification` is the only section allowed to claim the retained release bytes passed runtime qualification. Publication verifies the named workflow attempt and jobs live, downloads the one matching artifact, verifies every record byte, and re-resolves the immutable CLI tag. Well-formed hashes alone cannot authorize publication.

The AMD64 and ARM64 SaaS boot records remain exact-image evidence. Each boot
receives separate primary, cache, queue, and cable connection URLs and verifies
the four roles through Active Record together with the SaaS installation
identity. The retained qualification records expose only redacted role
outcomes, and the public manifest binds their hashes: database URLs are never
published, while adapter names and server versions are not release
requirements. A hosted Kamal deployment may still select PostgreSQL as its
runtime configuration.

The protected `source-release` environment is the runtime human gate. Promotion checks the current run's approval through GitHub's API but does not create or publish an approval attestation.

## Automated security policy

- `TRIGGERED` and `ASSIGNED` GitGuardian incidents are open and block publication.
- A confirmed credential is revoked or rotated before its incident is resolved.
- `IGNORED` is limited to a documented false positive or a test value proven incapable of authentication.
- Vulnerability waivers are exceptional, bounded to one finding and image digest, named by security role, and expire within 30 days. Anonymous, broad, unmatched, or expired waivers fail.
- Raw scanner diagnostics stay private to the trusted CI job. Public artifacts contain only non-sensitive status, counts, versions, identities, and hashes.

Run GitGuardian only in trusted CI with `GITGUARDIAN_DONT_LOAD_ENV=1`, `show_secrets: false`, and an appropriately scoped token:

```sh
ggshield secret scan repo .
ggshield secret scan path --recursive --yes --all-secrets .
ggshield secret scan docker ghcr.io/ivankuznetsov/screenote@sha256:<platform-digest>
```

Do not use `--exit-zero`, `--ignore-known-secrets`, ignored matches, ignored paths, ignored detectors, `--show-secrets`, `continue-on-error`, or shell constructs that discard scan status. The incident workflow separately verifies the matching repository source, active monitoring state, strict same-origin pagination, and every documented incident status.

## Public-log sentinel scan

Before promotion, scan release evidence, release notes, qualification records, SBOM/provenance metadata, and sanitized logs for:

- private key or certificate blocks;
- bearer-key prefixes and authorization headers;
- raw incident URLs, detector/match/location details, or credential values;
- absolute home, temporary, secret, backup, vault, object-storage, or internal-network paths;
- recovery/invitation links, query-string bearer values, and database connection URLs; and
- masking warnings showing that a secret reached a log.

A match blocks publication. Fix the underlying exposure; redacting a public copy alone is not remediation.

See [release dependency pins](action-pins.md) for immutable Action commits and checksum-pinned scanner/tool archives.
