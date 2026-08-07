# Support

## Hosted Screenote

For account or service questions about `screenote.ai`, email `support@screenote.ai`. Do not send credentials, private screenshots, recovery links, or vulnerability details in an ordinary support message; use [the security-reporting process](SECURITY.md).

## Self-hosted Screenote

The source-available self-hosted edition is provided as-is under the [O'Saasy License Agreement](LICENSE). Public issues may be used for reproducible bugs and focused feature requests after the repository is public. Community help and maintainer responses are best-effort and do not include an availability or response-time commitment.

Before asking for help:

- confirm that the deployment fork is based on an exact supported release,
  that application source and the running image digest match that release, and
  that fork changes are limited to documented deployment settings;
- follow every adjacent upgrade step from the named predecessor;
- read the [self-hosting guide](docs/self-hosting.md) and release-specific notes;
- reproduce without sharing customer content or secrets; and
- include sanitized edition, release digest, storage mode, proxy mode, and relevant error class.

Operators own their host, network, TLS termination, access controls, storage service, external email/provider accounts, monitoring, backups, restore drills, secret rotation, and capacity. A deployment fork pinned to an exact supported release is supported when its changes are limited to the documented non-secret Kamal settings. Application-code or dependency changes, modified Dockerfiles or entrypoints, custom images built from modified source, skipped upgrades, self-hosted PostgreSQL, clustering, high availability, storage migration, and infrastructure not listed in the release's support matrix are unsupported for the first release.

## Commercial and license questions

Questions about a competing hosted or managed offering, alternative commercial terms, or use outside the license grant should be sent privately to `support@screenote.ai`. Public issue discussion is not a license interpretation or legal approval.
