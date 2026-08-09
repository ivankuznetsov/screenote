# Self-host Screenote

Screenote is designed to run for a team on one server. The public self-hosted
path uses [ONCE](https://github.com/basecamp/once): no repository fork, source
checkout, Ruby installation, or local image build is required.

Start with the copyable [ONCE deployment guide](once-deployment.md).

## Supported shape

The initial self-hosted profile has:

- one non-root Screenote application container;
- Rails, Puma, and Solid Queue jobs in that container;
- four SQLite databases on one durable ONCE volume;
- local screenshot files on that volume by default; and
- ONCE's proxy in front of Screenote.

You do not need PostgreSQL, Redis, a separate worker, a billing service, or a
mail server. A private S3-compatible bucket and an external transactional email
provider are optional.

Screenote supports Linux servers with 64-bit Intel/AMD (x86-64) or ARM64
processors. Start with at least 2 vCPUs, 4 GiB of RAM, and 40 GiB of free SSD
storage. It is a single-instance baseline, not a cluster or high-availability
topology. Size the disk for database growth, screenshots, backups, and ordinary
filesystem headroom.

## Release boundary

The normal ONCE installation follows Screenote's latest published release:

```text
ghcr.io/ivankuznetsov/screenote:latest
```

ONCE automatic application updates remain disabled, so the operator decides
when to move to the latest release by running `once update HOST`. Each GitHub
Release also publishes its immutable image digest for auditing, pinning, and
version-pinned operation.

The hosted `screenote.ai` service uses an internal Kamal deployment. That is
separate from the public self-hosted workflow.

## Required configuration

ONCE creates Screenote's durable volume and `SECRET_KEY_BASE`. Screenote needs
two custom variables for its first boot:

- `SCREENOTE_BASE_URL` — the complete browser origin, such as
  `https://screenote.example.com`;
- `SCREENOTE_BOOTSTRAP_TOKEN` — a random, one-time token used to create the
  installation administrator.

Remove the bootstrap variable from ONCE immediately after the administrator
claim. The claim stays in the primary database and does not reopen when the
token disappears. Registration remains invitation-only.

The base URL controls links, allowed hosts, redirects, and cookie security. It
must be one origin without credentials, a path, query parameters, or fragment.
Use HTTPS for internet-facing installations. Plain HTTP is appropriate only
when a private VPN is the accepted transport boundary; deploy with ONCE's
`--disable-tls` option and use the matching `http://` base URL.

The supported ONCE path has two internal forwarding hops: ONCE's proxy and
Thruster. Screenote resolves the expected ONCE proxy with a bounded DNS lookup
before accepting the preceding client address and refreshes that identity in a
short synchronized cache. A failed refresh discards the stale identity. The
boundary then discards any values supplied before the verified client and
derives HTTP versus HTTPS from `SCREENOTE_BASE_URL`. Traffic that bypasses the
proxy, or arrives while its identity cannot be refreshed, is attributed to its
actual final hop instead of a supplied address. This keeps session auditing and
IP rate limits distinct without accepting caller-supplied transport identity.
Additional reverse proxies are outside the first release's qualified topology.

## Storage

Local storage needs no configuration. ONCE mounts the same persistent volume
at `/storage` and `/rails/storage`, where Screenote keeps all four SQLite
databases and local screenshot files.

S3 mode moves screenshot files only. The databases stay on the volume. Before
the team uploads screenshots, set:

- `SCREENOTE_STORAGE=s3`;
- `SCREENOTE_S3_ENDPOINT`, `SCREENOTE_S3_REGION`, `SCREENOTE_S3_BUCKET`, and a
  stable `SCREENOTE_S3_PREFIX`;
- `SCREENOTE_S3_ACCESS_KEY_ID` and `SCREENOTE_S3_SECRET_ACCESS_KEY`; and
- `SCREENOTE_S3_PATH_STYLE=false` only when the provider requires it.

Use a dedicated private bucket and prefix. Rotating credentials without
changing that namespace is supported. Moving existing objects to another
endpoint, bucket, or prefix is a storage migration and is not part of the
initial workflow.

## Email and invitations

Core review works without email. Project owners can copy a private invitation
link or manual code from **Members** and share it through a trusted channel.

For automatic delivery, add Resend, Postmark, or another SMTP provider through
ONCE's Email settings. ONCE passes the SMTP server, port, username, password,
and verified sender address to Screenote. Screenote rejects an incomplete
enabled email configuration instead of silently dropping messages.

## Backups and recovery

ONCE backups include the application settings and persistent volume. With local
storage, that covers the four databases and screenshot files. ONCE pauses the
Screenote container while copying the volume so the SQLite backup is
consistent.

Backups contain private data and retained settings, including secrets. Keep
them outside the application volume, restrict access, encrypt them at rest,
and copy them off the server. With S3 storage, protect the bucket separately
and recover it to the matching database recovery point.

Complete an isolated restore drill before storing important work and before
each upgrade. Verify sign-in, projects, screenshots, annotations, comments,
invitations, and queued image processing after the restore. Operators own the
host, network, TLS, access controls, provider accounts, capacity, monitoring,
backup retention, secret recovery, and tested restores.

The normal `latest` installation restores data and settings onto the current
release. It does not preserve the historical application version. Operators
that require version-pinned rollback must use the immutable image reference
published with each GitHub Release instead of the simple moving channel.

## Updates

Before an update:

1. read the new release's migration and recovery notes;
2. take and verify a recoverable ONCE backup;
3. run `once update HOST`.

The ONCE update preserves the application's environment and other settings. If
a release requires special maintenance, follow its release notes.

## Connect agents

The [Screenote CLI](https://github.com/ivankuznetsov/screenote-cli) is the
machine-readable interface for captures and feedback. The
[Screenote agent plugin](https://github.com/ivankuznetsov/agent-plugins/tree/main/plugins/screenote)
teaches coding agents how to use that CLI. Install the exact CLI tag named by
the Screenote release and point it at `SCREENOTE_BASE_URL`; browser or device
login keeps access scoped to the projects that user can reach.

See [SUPPORT.md](../SUPPORT.md) for the support boundary and
[SECURITY.md](../SECURITY.md) for private vulnerability reporting.
