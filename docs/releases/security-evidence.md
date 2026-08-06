# Release security evidence

Every evidence item is bound to one exact source SHA and the exact OCI platform/manifest digests. Evidence is split so public transparency never publishes the sensitive material needed to attack an operator or credential provider.

## Public evidence

The committed or released public manifest may contain only:

- schema and policy versions;
- the repository and exact commit;
- the canonical Fizzy O'Saasy source URL, reviewed upstream commit, and SHA-256 hashes of the fetched source and adapted Screenote license;
- semantic release tag, predecessor declaration, and exact public CLI tag;
- opaque preauthorization, run, incident-disposition, ruleset, and evidence identifiers;
- SHA-256 hashes of reviewed evidence, ruleset exports, source/ref inventories, SBOM, provenance bundle, logs, and scan reports;
- scanner, database, and policy versions;
- counts and pass/fail dispositions without paths, matches, secret types, or vulnerability detail;
- exact OCI platform and manifest digests; and
- source-contract conclusions explicitly labelled `pr_contract_only`, never presented as release qualification;
- the exact release-qualification workflow run/attempt, artifact archive and record hashes, candidate/CLI identities, minimum-host profile hash, platform digests, and eight redacted check-record hashes; and
- preauthorization timestamps and role labels without personal notes.

Use [`evidence/public-evidence.example.json`](evidence/public-evidence.example.json) as the schema template. `bin/release-validate` rejects unknown fields, placeholder values, malformed hashes/digests, nonzero open incidents or unwaived Critical/High counts, expired waivers, mismatched source SHAs, and sensitive-key/path sentinels.

`artifacts.evidence_sha256` is the SHA-256 of the retained `screenote-candidate.tar`; `sbom_sha256` is the hash of its canonical two-platform SBOM-set manifest; and `provenance_sha256` is the hash of its retained provenance input. The promotion authorization downloads the named artifact from the exact successful candidate workflow run and rechecks all three before any external mutation.

`source_contracts` records protected-main CI conclusions only. In particular, its `public-cli`, `container-local`, and `backup-restore` jobs validate source-level contracts or independently built smoke paths; they do not claim that retained release bytes passed CLI, final-image, restore, or load qualification. Only `qualification` may carry `status: passed`, and only after the separate workflow emits the exact eight check records. Authorization queries the named workflow attempt and jobs live, selects one non-expired artifact by live ID and archive digest, validates every downloaded byte against the committed record hashes, and re-resolves the CLI tag to its qualified commit. Missing or expired Actions evidence blocks publication even when every committed hash is well formed.

The manifest's `preauthorization` object records a reviewed release-maintainer decision and the intended `source-release` target. Its exact role, opaque ID, timestamp, and restricted-evidence hash are validated, but it is not a GitHub protected-environment approval. GitHub supplies that separate runtime gate after the promotion job enters the protected environment. Promotion publishes a redacted `environment-approval.json` release asset containing only repository/source/authorizing bindings, workflow run ID and attempt, environment/state, and the SHA-256 of the canonical complete GitHub review object. It never contains reviewer identity or comment. Exact resumptions re-fetch the named historical run's review history and reject missing, multiple, changed, or mismatched history before comparing immutable release bytes.

The implementation snapshot observed <https://www.fizzy.do/license> on 2026-08-06 with response SHA-256 `2a430f872f3203a6ae699fa00eb2d889bb2d06062f8cbe1add79ad6eb2bebe34`; the corresponding `basecamp/fizzy` `LICENSE.md` at commit `fa1fe476ff3844e4cfc5bb88c1b1947be29abc08` had SHA-256 `ba80f19e780db9c25f48af4175c6d7b94f984b614d0062007dbf9357c41cab56`. The adapted Screenote `LICENSE` has SHA-256 `270fc922f0483dc3cc6757c18e2e2c83093b5eeaf1adcf6bd5ff70df3e8790dc`. Release evidence must refresh these snapshots and legal review must compare the substantive text; hashes alone are not approval.

## Restricted evidence

Store the following only in a separately access-controlled evidence system:

- credential inventory and authorized decryption output;
- incident IDs, detector types, matches, locations, validity checks, and remediation notes;
- vulnerability package/CVE details, exploitability analysis, and waiver justification;
- provider rotation/revocation records;
- full repository-surface audit notes and confidential-data or intellectual-property findings;
- legal advice, chain-of-title documents, and approver identity;
- scanner raw output, workflow logs with internal paths, and backup/restore detail; and
- private configuration, secret-bundle references, or storage object inventories.

Restricted evidence must have named access owners, audit logging, retention and deletion dates, encryption at rest and in transit, and a deletion hold for an active incident. The repository records only an opaque ID plus a SHA-256 hash of the finalized restricted record. Never upload restricted evidence as a public Action artifact.

## Required disposition rules

- `TRIGGERED` and `ASSIGNED` GitGuardian incidents are Open and block publication.
- A confirmed credential is revoked or rotated before the incident is marked `RESOLVED`, even when exposure seems low risk.
- `IGNORED` is permitted only for an authorized, documented false positive or a non-secret test value proven incapable of authentication.
- Reviewed history containing a revoked credential may remain only with explicit security and legal approval.
- A non-revocable secret, protected personal/confidential data, third-party intellectual property, missing decryption authority, or uncertain license authority requires publication to stop for a reviewed history rewrite or clean public root.
- Vulnerability waivers are exceptional, named, bounded to exact finding and image digest, approved by the security role, and expire before the next release. Anonymous, broad, unmatched, or expired waivers fail.

## GitGuardian commands

Run only in trusted CI with `GITGUARDIAN_DONT_LOAD_ENV=1`, `show_secrets: false`, and an appropriately scoped GitGuardian token:

```sh
ggshield secret scan repo .
ggshield secret scan path --recursive --yes --all-secrets .
ggshield secret scan docker ghcr.io/ivankuznetsov/screenote@sha256:<platform-digest>
```

Do not use `--exit-zero`, `--ignore-known-secrets`, ignored matches, ignored paths, ignored detectors, `--show-secrets`, `continue-on-error`, or shell constructs that discard a scan status. Retain redacted reports privately and publish only their hashes, versions, counts, and dispositions.

`ggshield` documents that a successful scan returns zero while detections and operational failures return nonzero: <https://docs.gitguardian.com/ggshield-docs/reference/overview>. Docker scanning covers build history and image layers: <https://docs.gitguardian.com/ggshield-docs/reference/secret/scan/docker>.

The incident workflow uses GitGuardian's documented Retrieve Source and List secret incidents endpoints. It accepts only a matching GitHub source whose `monitoring_status` is exactly `active`, rejects archived/deleted provider metadata, follows only strict same-origin cursor links, and counts only statuses in the documented `IGNORED`, `TRIGGERED`, `ASSIGNED`, and `RESOLVED` set. A completed history scan is proven separately by `gitguardian.app_check.history_scan` and the retained source-scan record; absence of either blocks publication.

GitHub runs `pull_request_target` on the trusted base revision rather than the pull request commit. Before contacting GitGuardian, the workflow therefore posts its single named `pending` status to the validated 40-character PR head and test-merge SHAs through GitHub's fixed API origin. It replaces that status with `success` only after the metadata gate passes, or with generic `error` on failure; if error publication fails, pending remains blocking. It never checks out or executes pull-request data. The token has only `contents: read` and `statuses: write`; a missing token, malformed SHA, API error, or absent status blocks the ruleset instead of being treated as success. Live protection evidence must prove that the required status is present on the exact commit GitHub requires for merging and that ready/reopen/synchronize events refresh stale results.

See [release dependency pins](action-pins.md) for immutable Action commits and checksum-pinned scanner/tool archives.

## Public-log sentinel scan

Before promotion, scan all proposed public evidence, release notes, SBOM/provenance metadata, and sanitized workflow logs for:

- private key or certificate blocks;
- common bearer-key prefixes and authorization headers;
- raw GitGuardian incident URLs, detector/match/location details, or credential inventories;
- absolute home, temporary, runner, backup, vault, bucket-object, and internal network paths;
- runtime secret values, recovery/invitation links, query-string bearer values, and database connection URLs; and
- GitHub masking warnings that indicate a secret appeared in a log.

A sentinel match blocks publication and moves the detailed artifact into restricted incident handling. Redacting a public copy does not resolve the underlying incident.
