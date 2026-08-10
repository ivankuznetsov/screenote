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
  <a href="docs/once-deployment.md">Operator guide</a>
</p>

Screenote is a visual review workspace for screenshots. It gives people a
Figma-like place to leave precise feedback while giving automation a structured
way to publish captures and read the result.

## How it works

1. **Publish** — your agent, browser tool, or CI job produces PNG/JPEG captures
   and publishes one screen or a multi-page snapshot.
2. **Review** — teammates open the authenticated review URL, switch between
   desktop, tablet, and mobile captures, and add point or area comments.
3. **Close the loop** — people reply in context while an agent reads the open
   annotations and available image crops, applies the fix, and resolves the
   thread with a final comment through the Screenote CLI.

## What you get

- Projects organized into pages, versions, and capture snapshots
- Desktop, tablet, and mobile review in one workspace
- Point and rectangular-area annotations with threaded replies
- Resolve and reopen workflows for multi-person review
- Private screenshots and review URLs protected by project membership
- OAuth browser and device login for local, SSH, and headless clients
- A JSON CLI for uploads, comments, crops, and automation
- A companion [Screenote agent skill](https://github.com/ivankuznetsov/agent-plugins/tree/main/plugins/screenote)
  that teaches coding agents the CLI workflow

## Choose how to run it

| | Hosted | Self-hosted |
| --- | --- | --- |
| Best for | Starting immediately | Keeping Screenote inside your VPN or infrastructure |
| Operations | Managed at [screenote.ai](https://screenote.ai) | [ONCE](https://github.com/basecamp/once), one application server, and one durable volume |
| Screenshot storage | Managed | Local by default; S3-compatible storage is optional |
| Setup | Create an account | First visitor creates the administrator, then invites teammates |

Screenote is **source-available and self-hostable** under the
[O'Saasy License Agreement](LICENSE).

## Self-host Screenote

Screenote runs with [ONCE](https://github.com/basecamp/once) as one application
container with one durable volume. The container includes the Rails app,
background jobs, four SQLite databases, and local screenshot storage. You do
not need PostgreSQL, Redis, a separate worker, or a mail server.

### Install with your agent

Copy this prompt into a coding agent that can access your server. It will ask
for the hostname or SSH destination only when they are missing.

```text
Install Screenote for my team using the simplest supported self-hosted setup.

Work on the target Linux server. If you are not already connected to it, ask me
for the SSH destination. Ask me for the Screenote hostname if I have not given
one; treat screenote.example.com as an example, not a real value. Run the setup
yourself instead of asking me to copy individual commands.

1. Verify the server is 64-bit x86-64 or ARM64 Linux with at least 2 vCPUs,
   4 GiB RAM, 40 GiB free SSD storage, and ports 80 and 443 available. Confirm
   the hostname resolves to this server. Ask before changing DNS or firewall
   rules.
2. Install released stock ONCE with:
   curl https://get.once.com | ONCE_INTERACTIVE=false sh
3. If the installer added the current non-root user to the Docker group, start
   a fresh login session before continuing.
4. Deploy Screenote, replacing HOST with the real hostname:
   once deploy ghcr.io/ivankuznetsov/screenote:latest --host HOST --env SCREENOTE_BASE_URL=https://HOST
5. Keep the default local screenshot storage and ONCE automatic updates. Do not
   configure SMTP, S3, OAuth, or monitoring unless I ask for them.
6. Wait until https://HOST/up and https://HOST/ready both return HTTP 200. If a
   check fails, inspect ONCE and application logs, fix recoverable problems, and
   retry. Stop only for a concrete external blocker that requires my action.
7. When Screenote is healthy, give me its URL and tell me to create the first
   administrator immediately. Do not open the setup page, create an account, or
   complete the first-administrator claim yourself. Do not choose, request,
   store, or print my administrator password. The first completed setup claims
   the instance; all later accounts are invitation-only.
8. Finish with a short summary of what changed, the health checks you ran, and
   the next backup step. Never expose secrets in commands, logs, or the summary.
```

### Install manually

Prepare a Linux server with a 64-bit Intel/AMD (x86-64) or ARM64 processor,
point a hostname at it, and open ports 80 and 443. Install released stock ONCE,
then deploy Screenote with the hostname and matching canonical URL:

```sh
curl https://get.once.com | ONCE_INTERACTIVE=false sh
```

If ONCE just installed Docker for your non-root user, reconnect to the server
once before continuing. Then deploy Screenote:

```sh
once deploy ghcr.io/ivankuznetsov/screenote:latest \
  --host screenote.example.com \
  --env SCREENOTE_BASE_URL=https://screenote.example.com
```

ONCE installs Docker when needed and keeps automatic updates enabled. Open the
hostname and create the first administrator. Do this immediately after
installation: the first person to complete setup atomically claims the new
instance. Afterward, Screenote is invitation-only.

Create a project and invite your team. Email is optional; ONCE's Email settings
accept SMTP credentials from services such as Resend or Postmark. Local
screenshot storage works immediately. The operator guide includes a separate
advanced first-deployment path for a private S3-compatible bucket or HTTP-only
VPN hostname.

ONCE applies Screenote updates automatically. To update immediately, take a
backup and run:

```sh
once update screenote.example.com
```

Read [Deploy with ONCE](docs/once-deployment.md) for VPN-only HTTP, email, S3,
backups, restores, and updates. The broader
[self-hosting guide](docs/self-hosting.md) explains the production boundary.

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
screenote annotation resolve --annotation <ANNOTATION_ID> --comment "Fixed in abc123"
```

Agents use the CLI to read threads, add replies, and resolve a thread with an
optional final comment. Reopening remains available in the web review UI; the
CLI does not expose it yet. The CLI emits machine-readable JSON.
For multi-page and multi-viewport uploads, use the manifest reference from the
same tested CLI tag:
`https://github.com/ivankuznetsov/screenote-cli/blob/<release-cli-tag>/docs/snapshot-manifest.md`.
For coding agents, install the
[Screenote agent plugin](https://github.com/ivankuznetsov/agent-plugins/tree/main/plugins/screenote)
and point its CLI at the same Screenote origin. The plugin teaches the agent
the capture, upload, and feedback loop; the CLI remains the integration
boundary.

## Develop Screenote

Screenote is a Rails 8.1 application. Prepare the databases, start the
development processes, and run the repository quality gate with:

```sh
bin/setup
bin/dev

# Before opening a pull request
bin/ci
script/release_test_matrix self-hosted
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
