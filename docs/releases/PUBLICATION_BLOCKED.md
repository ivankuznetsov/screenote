# Publication is blocked

This file is an executable release sentinel. While it exists, `bin/release-validate --mode publish` and `.github/workflows/release.yml` must fail before creating a tag, pushing an image, generating a public attestation, or creating a GitHub release.

It may be removed only in a separately reviewed release-authorizing change after restricted evidence proves all of the following:

- Future Spin Ltd's chain of title and authority to use the exact O'Saasy text and copyright notice have legal approval.
- Third-party source, dependency, base-image, asset, and history licensing has legal approval.
- GitGuardian is authorized for this exact repository source; its historical scan and the explicit full-history/current-tree scans completed for the candidate commit; and every incident is closed under the documented disposition policy.
- The removed encrypted Rails credentials have been inventoried under authorized decryption, every reusable value has been rotated or revoked, and security plus legal reviewers approved either history retention or a reviewed rewrite/clean root.
- Main and release-tag rulesets, the GitGuardian App required check, metadata-only incident check, protected `source-release` environment, private vulnerability reporting, immutable GitHub releases, and GHCR permissions are configured and independently inspected.
- The canonical public CLI has an immutable tested tag.
- Exact AMD64/ARM64 layouts, manifest digest, SBOM, provenance, secret scans, vulnerability scans, source-contract checks, and public-log sentinel scan are retained and match the candidate commit.
- The separate qualification workflow has configured ephemeral native AMD64/ARM64 runners, a versioned minimum-host profile, a tracked real load driver, a tracked tagged-CLI HTTP/HTTPS driver, and candidate-backed origins. Its exact retained artifact proves all eight runtime checks; PR contract jobs are not accepted as substitutes.

Deleting this sentinel does not itself authorize publication. The protected release environment still requires explicit maintainer approval and `bin/release-validate` must pass against the final redacted evidence manifest.
