# Self-host Screenote

Screenote is designed to run as a small, single-server Rails application for a
team. The repository includes a [Kamal](https://kamal-deploy.org/) starter
configuration, and [Kamal Proxy](https://kamal-deploy.org/docs/configuration/proxy/)
handles HTTPS and routes traffic to the application.

> [!IMPORTANT]
> The first supported source release is still being prepared. Until a version
> appears on [GitHub Releases](https://github.com/ivankuznetsov/screenote/releases),
> treat deployment from this repository as a development preview.

For a copyable walkthrough, start with the
[Kamal deployment guide](kamal-deployment.md).

## What runs on your server

The default self-hosted deployment has:

- one Screenote application container, with Solid Queue jobs supervised by
  Puma;
- Kamal Proxy in front of the application;
- four SQLite databases on the `screenote_storage` named volume; and
- local screenshot files on that same volume.

You do not need PostgreSQL, Redis, a separate worker, a billing service, or a
mail server. S3-compatible screenshot storage and external transactional email
are optional.

The first-release host profile is Linux AMD64 with at least 2 vCPUs, 4 GiB of
RAM, and 40 GiB of free local SSD storage. It is a single-instance baseline,
not a high-availability topology. Size storage for the screenshots you plan to
keep as well as database growth, backup headroom, and normal filesystem use.

## Before you deploy

Prepare:

- a Linux server reachable over SSH;
- a hostname pointed at that server;
- ports 80 and 443 available to Kamal Proxy when it manages HTTPS;
- Docker with Buildx on the workstation or CI runner that mirrors the release
  image (or builds an explicitly unsupported development image); and
- Ruby and Bundler for running this repository's `bin/setup` and `bin/kamal`
  wrappers.

Fork the repository before customizing `config/deploy.yml`. Your fork gives
the deployment configuration a stable home and makes later Screenote updates
reviewable before they reach your team.

On a supported release, `bin/kamal setup` and `bin/kamal deploy` validate the
immutable `public-evidence.json` release asset and mirror its exact qualified
image manifest through Kamal's loopback registry. Only `config/deploy.yml` may
differ from the tagged source in the supported first-release workflow. The
wrapper never rebuilds the supported image.

## Configuration boundaries

`config/deploy.yml` is the self-hosted starter. At minimum, replace the example
host in these settings:

- `servers.web` — the server Kamal reaches over SSH;
- `ssh.user` — the SSH account, if it is not `root`;
- `proxy.host` — the public Screenote hostname; and
- `env.clear.SCREENOTE_BASE_URL` — the complete public `https://` origin.

The starter has two private proxy hops: Kamal Proxy on Docker's private network
and Thruster on application-container loopback. Kamal Proxy discards incoming
forwarding values and creates authoritative ones; Thruster passes them to
Rails. The starter trusts only those two internal ranges and does not publish
either application port directly. Keep `proxy.forward_headers`,
`THRUSTER_FORWARD_HEADERS`, and `SCREENOTE_TRUSTED_PROXIES` together. Do not
replace the trusted ranges with an internet-wide, LAN, or VPN-wide range.

Kamal reads secrets from `.kamal/secrets`, which is ignored by Git. Start from
`.kamal/secrets.example`; never commit the populated file, paste its values
into logs or issues, or store it only on the Screenote server. Keep a protected
recovery copy of `SECRET_KEY_BASE` outside the application volume.

The bootstrap token is needed only to claim a new installation. After the
administrator has claimed it, remove `SCREENOTE_BOOTSTRAP_TOKEN` from both the
Kamal secret list and `.kamal/secrets`, then deploy once more. The claim is
stored in the database and does not reopen when that token is removed.

## TLS and VPN installations

With `proxy.ssl: true` and a publicly resolvable hostname, Kamal Proxy obtains
and renews the TLS certificate. DNS must point at the server before the first
deployment.

For a private VPN hostname, use a certificate and ingress arrangement that is
valid for that hostname. Plain HTTP is appropriate only when your VPN provides
the trusted transport boundary and your team accepts the loss of browser-level
HTTPS protections. If you choose HTTP, set `proxy.ssl: false` and make
`SCREENOTE_BASE_URL` use the matching `http://` origin.

The base URL controls links, allowed hosts, redirects, and cookie security. It
must be one origin without credentials, a path, query parameters, or a
fragment.

## Screenshot storage

Local storage is the default. It keeps SQLite state and screenshot files on the
`screenote_storage` named volume mounted at `/rails/storage`.

To use a private S3-compatible bucket instead, make the change before the first
deployment:

1. Set `SCREENOTE_STORAGE` to `s3` in `config/deploy.yml`.
2. Fill in the endpoint, region, bucket, stable prefix, and path-style settings.
3. Add `SCREENOTE_S3_ACCESS_KEY_ID` and
   `SCREENOTE_S3_SECRET_ACCESS_KEY` to `env.secret`.
4. Put those two values in `.kamal/secrets`.

The SQLite databases remain on the named volume. Changing S3 credentials for
the same namespace is a credential rotation; changing the endpoint, bucket, or
prefix after blobs exist is a storage migration and is not part of the initial
self-hosted workflow.

## Email through Resend, Postmark, or another provider

Screenote does not include or operate an SMTP server. Core review works without
email: project owners can copy a private invitation link or manual code from
the Members screen and share it through a trusted channel.

To send invitations automatically, connect an external transactional provider
that offers SMTP, such as Resend or Postmark:

1. Set `SCREENOTE_SMTP_ENABLED` to `true` in `config/deploy.yml`.
2. Fill in the provider's SMTP address, port, username, authentication,
   STARTTLS setting, and your verified `MAILER_FROM` address.
3. Add `SMTP_USERNAME` and `SMTP_PASSWORD` to `env.secret`.
4. Put both provider-issued credential values in `.kamal/secrets`. Some
   providers use a secret token as the SMTP username, so neither value belongs
   in tracked configuration.

The commented Resend settings in `config/deploy.yml` are an example. Use the
values supplied by your chosen provider. Screenote rejects incomplete enabled
email configuration at startup instead of silently dropping mail.

## Claim and invite the team

The first deployment opens `/bootstrap`. Enter the one-time bootstrap token and
create the single instance administrator. Open registration remains disabled.

After claiming the instance:

1. Create a project.
2. Open **Members** and invite each collaborator.
3. Send the private link or manual code directly, or let the configured email
   provider deliver it.

New teammates create durable local credentials while accepting the invitation.
Every project page, screenshot, and review URL continues to enforce project
membership.

## Operate and back up the instance

- `/up` is the process liveness endpoint.
- `/ready` verifies the application databases and writable storage used by the
  deployment health check.
- `bin/kamal logs` follows application logs.
- `bin/kamal console` opens a Rails console inside the running application.
- `bin/kamal diagnostics` runs the built-in self-hosted diagnostics inside the
  application container.

Before storing important work, configure encrypted backups for the
`screenote_storage` named volume and complete a restore drill. A valid backup
must capture a consistent, quiesced copy of all four SQLite databases and, in
local-storage mode, every screenshot file. Retain the matching deployment
configuration and application secrets in a separate protected recovery system.
For S3 mode, protect and test recovery of the dedicated bucket and prefix as a
separate part of the same recovery point.

Operators own host and network security, TLS, provider accounts, capacity,
monitoring, backup retention, secret recovery, and tested restores.

## Update Screenote

Use only a supported version from
[GitHub Releases](https://github.com/ivankuznetsov/screenote/releases). Review
its release notes. Replace `vNEXT` below with that exact tag, fetch it from the
canonical repository configured during initial setup, review the merge into
your deployment branch, update the local bundle, and deploy:

```sh
git fetch upstream tag vNEXT
git merge --no-ff vNEXT
bin/setup --skip-server
bin/kamal deploy
```

Do not skip a release when its notes require an adjacent upgrade, and do not
attach old application code to storage already migrated by newer code. Take
and verify a recoverable backup before every upgrade.

## Connect agents

The [Screenote CLI](https://github.com/ivankuznetsov/screenote-cli) is the
machine-readable interface for captures and feedback. The
[Screenote agent plugin](https://github.com/ivankuznetsov/agent-plugins/tree/main/plugins/screenote)
teaches coding agents how to use that CLI. Point both at your
`SCREENOTE_BASE_URL`; browser or device login keeps access scoped to the
projects that user can reach.

See [SUPPORT.md](../SUPPORT.md) for the support boundary and
[SECURITY.md](../SECURITY.md) for private vulnerability reporting.
