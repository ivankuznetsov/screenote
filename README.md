<p align="center">
  <img src="public/icon.svg" width="96" height="96" alt="Screenote logo">
</p>

<h1 align="center">Screenote</h1>

<p align="center">
  <strong>Turn screenshot feedback into work your team and coding agents can act on.</strong>
</p>

<p align="center">
  Publish a capture, point to or draw around the problem, discuss it in context,<br>
  and let your agent retrieve the comment and available image crop through the CLI.
</p>

<p align="center">
  <a href="https://screenote.ai">Try Screenote</a> ·
  <a href="#self-host-screenote">Self-host</a> ·
  <a href="https://github.com/ivankuznetsov/screenote-cli">CLI</a> ·
  <a href="docs/self-hosting.md">Operator guide</a>
</p>

Screenote is a visual review workspace for screenshots. It gives people a
Figma-like place to leave precise feedback while giving automation a structured
way to publish captures and read the result.

## How it works

1. **Publish** — your agent, browser tool, or CI job produces PNG/JPEG captures
   and publishes one screen or a multi-page snapshot.
2. **Review** — teammates open the authenticated review URL, switch between
   desktop, tablet, and mobile captures, and add point or area comments.
3. **Close the loop** — people reply and resolve threads while an agent reads
   open annotations and cropped regions through the CLI, REST API, or MCP.

## What you get

- Projects organized into pages, versions, and capture snapshots
- Desktop, tablet, and mobile review in one workspace
- Point and rectangular-area annotations with threaded replies
- Resolve and reopen workflows for multi-person review
- Private screenshots and review URLs protected by project membership
- OAuth browser and device login for local, SSH, and headless clients
- A JSON CLI for uploads, comments, crops, and automation
- REST and MCP integration surfaces for agent workflows
- A self-hosted core with no Stripe, license key, or application-enforced
  seat, project, or screenshot-count caps

## Choose how to run it

| | Hosted | Self-hosted |
| --- | --- | --- |
| Best for | Starting immediately | Keeping Screenote inside your VPN or infrastructure |
| Operations | Managed at [screenote.ai](https://screenote.ai) | One Linux container and one durable volume |
| Screenshot storage | Managed | Local by default; S3-compatible storage is optional |
| Product caps | SaaS plan applies | No application-enforced seat, project, or screenshot-count caps |
| Setup | Create an account | Claim the instance once, then invite teammates |

Screenote is **source-available and self-hostable** under the
[O'Saasy License Agreement](LICENSE). It is not distributed under an
OSI-approved open-source license.

## Self-host Screenote

> [!IMPORTANT]
> The self-hosted edition is implemented in this repository, but the first
> supported source release has not been published yet. There is currently no
> supported source tag, container digest, or tested CLI tag. Until those appear on
> [GitHub Releases](https://github.com/ivankuznetsov/screenote/releases), use
> [screenote.ai](https://screenote.ai) or run the repository as a development
> build—do not operate an untagged branch, a moving image tag, or a candidate
> build as a supported release.

The supported first-release design is intentionally small:

- one non-root Screenote container;
- four SQLite databases and local screenshot files on one durable Docker
  volume; and
- optional S3-compatible screenshot storage, SMTP, social sign-in, and
  monitoring through additive Compose files.

There is no PostgreSQL service, Redis service, worker container, or billing
service to provision for the default self-hosted setup.

### Initial Docker setup requirements

- A Linux AMD64 host with at least 2 vCPUs, 4 GiB RAM, and 40 GiB free local
  SSD space
- Docker Engine with the Docker Compose plugin
- `openssl` for generating the two initial secrets
- A stable VPN or HTTPS URL for your team
- Host files owned by UID/GID `1000:1000`, the supported container identity

> [!WARNING]
> The host-operations installation has not been published yet. The current
> source-tree diagnostics, backup, and restore wrappers require `bundler/setup`,
> and their shared code requires `sqlite3`, from the matching project bundle.
> Ruby 3.4.10 and Bundler alone are not sufficient, and these scripts are not a
> standalone Docker-only operator package. Before the first supported release
> is published, its release notes must name or provide the exact
> release-matched host-operations installation or bundle. Until then, the
> operations linked below describe the intended release contract, not a
> supported runnable toolkit.

### 1. Check out a published release

Open that release's notes and copy its exact server tag and
`ghcr.io/ivankuznetsov/screenote@sha256:…` image reference. Then check out that
tag—not `main`:

```sh
RELEASE_TAG=vX.Y.Z # replace with the exact tag from GitHub Releases
git clone --depth 1 --branch "$RELEASE_TAG" https://github.com/ivankuznetsov/screenote.git
cd screenote
cp .env.self-hosted.example .env
chmod 0600 .env
```

### 2. Set deployment values and choose ingress

Edit `.env` and replace the image reference:

```dotenv
SCREENOTE_IMAGE=ghcr.io/ivankuznetsov/screenote@sha256:REPLACE_WITH_RELEASE_DIGEST
```

For HTTPS, set the public origin and trust only the immediate reverse proxy
peer or peers:

```dotenv
SCREENOTE_BASE_URL=https://screenote.example.com
SCREENOTE_TRUSTED_PROXIES=REPLACE_WITH_IMMEDIATE_PROXY_IP
```

Replace that proxy placeholder with only the exact IP address or narrow CIDR
of each immediate proxy peer, comma-separated. Do not trust an entire LAN,
VPN, cloud network, or internet-wide range for convenience. Configure that
proxy and TLS before starting the bootstrap service, following the
[reverse-proxy requirements](docs/self-hosting.md#reverse-proxy-and-tls).

For the simpler trusted-VPN direct-HTTP alternative, explicitly keep proxy
trust empty and accept the transport risk:

```dotenv
SCREENOTE_BASE_URL=http://screenote.internal:3005
SCREENOTE_TRUSTED_PROXIES=
```

Keep the default `SCREENOTE_PORT=3005` unless that port is already in use.

Choose local or S3-compatible screenshot storage before the first boot. The
steps below use local storage. For S3, configure the
[S3 overlay](docs/self-hosting.md#use-s3-compatible-screenshot-storage) now and
include it in both the bootstrap and normal-mode commands; switching storage
after data exists is not supported by the first release.

### 3. Create the application and one-time claim secrets

Run these commands as UID 1000, or use equivalent privileged commands that
produce the exact ownership and modes shown:

```sh
install -o 1000 -g 1000 -m 0700 -d secrets
umask 077
openssl rand -base64 48 > secrets/secret_key_base
openssl rand -base64 48 > secrets/bootstrap_token
chmod 0400 secrets/secret_key_base secrets/bootstrap_token
chown 1000:1000 secrets/secret_key_base secrets/bootstrap_token
```

Keep an encrypted copy of `secret_key_base` outside the Docker host. The
bootstrap token is temporary and should not be pasted into chat, logs, or an
issue.

### 4. Put ingress in place, then start and claim

For HTTPS, finish the TLS reverse proxy configuration from step 2 and restrict
direct access to port 3005 before exposing the bootstrap service. The proxy
must preserve the public host and forward the original scheme and client
address. For direct HTTP, keep the origin reachable only through the trusted
VPN and leave `SCREENOTE_TRUSTED_PROXIES` empty.

With that ingress boundary in place, validate the resolved Compose
configuration and start the bootstrap service:

```sh
docker compose -f compose.yaml -f compose.bootstrap.yaml config
docker compose -f compose.yaml -f compose.bootstrap.yaml up -d --wait
```

Open `<your Screenote URL>/bootstrap` through the selected ingress, enter the
bootstrap token, and create the instance administrator. After the claim
succeeds, remove the bootstrap secret and restart in normal mode:

```sh
docker compose -f compose.yaml -f compose.bootstrap.yaml down
rm secrets/bootstrap_token
docker compose -f compose.yaml up -d --wait
```

> [!CAUTION]
> Never add `--volumes` to `docker compose down`. The named volume contains the
> four databases and, in local-storage mode, every screenshot.

### 5. Add your team

1. Sign in with the administrator account and create a project.
2. Open the project, choose **Members**, and invite each collaborator by email.
3. Without SMTP, copy the private invitation link or manual code shown in the
   Members screen and send it to that person through a trusted channel. With
   the SMTP overlay enabled, Screenote also emails the invitation.

Open registration stays disabled. Every later account joins through an
invitation, new teammates create their password while accepting it, and every
review URL still checks project membership. Invitations expire after seven
days.

### Production checklist

- Keep the selected ingress boundary in place: HTTPS through only the
  configured immediate proxy peers, or direct HTTP only inside the trusted
  VPN. Continue to block proxy bypasses to port 3005.
- If you selected S3 before first boot, keep its overlay in every lifecycle and
  operations command; storage namespaces cannot be changed in place.
- Configure only the providers you need: [SMTP, Google, GitHub, or
  Honeybadger](docs/self-hosting.md#optional-providers).
- Use only the exact host-operations installation or bundle named by the
  release to run [diagnostics](docs/self-hosting/diagnostics.md) after startup.
- With that same release-matched host-operations environment, set up encrypted
  [backup and restore](docs/self-hosting/backup-and-restore.md) and complete a
  restore drill before storing important work.
- Follow only documented adjacent [upgrade and rollback](docs/self-hosting/upgrades.md)
  paths and keep every deployment pinned to its release digest.

The complete [self-hosting guide](docs/self-hosting.md) is the operator source
of truth for secrets, proxies, storage, health checks, backups, restores, and
upgrades.

## Connect the CLI or an agent

Each server release names one exact tested tag from the canonical
[Screenote CLI repository](https://github.com/ivankuznetsov/screenote-cli).
Install that tag, sign in to your Screenote origin, and select a project:

```sh
go install github.com/ivankuznetsov/screenote-cli/cmd/screenote@<release-cli-tag>
screenote --base-url https://screenote.example.com login
screenote project list
screenote config set --project <PROJECT_ID>
```

On SSH, tmux, a container, or another headless session, use device login:

```sh
screenote --base-url https://screenote.example.com login --device
```

Publish a complete capture set and work through its feedback:

```sh
screenote snapshot --manifest snapshot.json
screenote annotation list --screenshot <SCREENSHOT_ID> --status open
screenote annotation get --annotation <ANNOTATION_ID> --crop-file annotation.png
screenote comment add --annotation <ANNOTATION_ID> --body "Fixed in abc123"
screenote annotation resolve --annotation <ANNOTATION_ID> --comment "Ready for review"
```

The CLI emits machine-readable JSON. See its
[snapshot manifest reference](https://github.com/ivankuznetsov/screenote-cli/blob/main/docs/snapshot-manifest.md)
for multi-page and multi-viewport uploads.

## Develop Screenote

Screenote is a Rails 8.1 application. Prepare the databases, start the
development processes, and run the repository quality gate with:

```sh
bin/setup
bin/dev

# Before opening a pull request
bin/ci
SCREENOTE_EDITION=self_hosted PARALLEL_WORKERS=1 bin/rails test
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) before making a substantial change.

## Help, security, and license

- [Support boundary and troubleshooting](SUPPORT.md)
- [Private vulnerability reporting](SECURITY.md)
- [Release process and current status](docs/releases.md)
- [Third-party software notices](THIRD_PARTY_NOTICES.md)

Copyright © 2026, Future Spin Ltd.

Screenote is distributed under the [O'Saasy License Agreement](LICENSE). It
permits use, modification, and redistribution, but does not permit offering
Screenote or a derivative to third parties as a directly competing hosted,
managed, SaaS, or cloud service whose primary value is Screenote's
functionality. The license text—not this summary—is authoritative.
