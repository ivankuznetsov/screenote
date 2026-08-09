# Security policy

## Report a vulnerability privately

Do not open a public issue for a suspected vulnerability or exposed credential.

After the repository is public, use GitHub's **Report a vulnerability** form in the repository Security tab. Before that feature is enabled, or if it is unavailable, email `support@screenote.ai` with `[SECURITY]` in the subject. Share only the minimum reproduction needed and do not send live credentials or customer data by ordinary email; ask for a secure transfer method first.

Include the affected release digest or commit, deployment mode, impact, reproduction conditions, and whether you believe a credential or private data is exposed. We will acknowledge a usable report as soon as practical, coordinate remediation and disclosure, and credit reporters who want attribution when it is safe to do so. We do not promise a fixed response SLA for the source-available self-hosted edition.

## Supported releases

Security fixes are delivered through the current Screenote release. Self-hosted
operators using the normal ONCE setup receive them by running
`once update HOST`; release notes call out any required maintenance.

Modified source or custom images, untagged commits, and unsupported
infrastructure are outside the security-support promise. A vulnerability that
also affects a published Screenote release is still welcome regardless of where
it was found.

## Credentials and incident handling

A suspected secret immediately blocks default-branch updates and publication. Treat any confirmed credential as compromised and revoke or rotate it before resolving the incident. An incident may be ignored only when an authorized maintainer documents that it is a false positive or a non-secret test value incapable of authentication.

Do not paste a secret into an issue, pull request, review, Action log, artifact, release note, or evidence file. If a repository secret is exposed, contact the maintainer through the private reporting channel and rotate it at its provider; deleting the line from the latest commit is not sufficient.

## Security controls

The release process requires GitGuardian's history-aware GitHub App check, a separate paginated repository-incident check, full-history and current-tree `ggshield` scans, exact-image secret and Critical/High vulnerability scans, an SBOM, build provenance, protected rulesets, and a human-approved release environment. These controls are defense in depth and do not replace review.
