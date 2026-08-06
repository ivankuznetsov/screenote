# Tracked credential pre-publication audit

- Audit snapshot: 2026-08-06
- Candidate baseline: `bc029439035053bc2129ced8be366eda62c53817`
- Status: **publication blocked**

This is a redacted inventory of repository surfaces inspected without decrypting or printing secret material. It is not clearance for publication.

## Current-tree finding

`config/credentials.yml.enc` was tracked from the first Rails commit. Its ciphertext SHA-256 was `287bf73bfac53f69bafbafb04f853f6c38ff79a5984dd2bd0aa6edc203c8c775`; the Git blob identifier was `3f10f87bc6c2be8bf99a1330456fd9743c7bd659`. No `config/master.key` was tracked, and current application code had no `Rails.application.credentials` lookup.

The ciphertext is removed from the candidate current tree and encrypted-credential patterns are excluded from container build context. This prevents the unknown ciphertext from entering new source archives and images, but it remains reachable in candidate history until reviewers decide whether history may be retained.

## Read-only history surface snapshot

- Commits touching the encrypted credentials path: `1`.
- SHA-256 of the ordered touching-commit list: `e7ad51aeaa097d4d5d6f190bb3ba63eded3e6d36821dc974c69aa24528e3406a`.
- SHA-256 of the ordered ref-name/object-id inventory: `e97cc6f7f1fa5c22e70fd22403471c42a2ec85c0c185c970d0e6b379abea7e71`.
- SHA-256 of the ordered reachable-object/path inventory: `6b08ade10368df365225a5407f528d395888c0ad0285c8bc4b74a01205de9c03`.

These hashes describe only the baseline snapshot and must be regenerated after the write freeze. They do not prove that unreachable objects, forks, GitHub caches, logs, artifacts, issues, pull requests, wiki pages, releases, packages, Pages output, or provider-side copies are clear.

## Blocking disposition

The decryption key and authority were not available to this implementation task, so the ciphertext was not decrypted, classified, or treated as safe. Publication remains blocked until an authorized reviewer:

1. inventories the decrypted keys and values in restricted evidence without copying them into source or public logs;
2. identifies every provider and environment that could accept a reusable value;
3. revokes or rotates every confirmed credential before closing its incident;
4. binds provider records and the GitGuardian full-history/current-tree results to the frozen candidate SHA; and
5. obtains security and legal approval to retain the historical ciphertext, or publishes a reviewed history rewrite/clean root.

No raw credential, decrypted value, incident detail, or provider record belongs in this file.
