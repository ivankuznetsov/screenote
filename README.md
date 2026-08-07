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
   open annotations and available image crops through the Screenote CLI.

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
- A self-hosted core with no Stripe, license key, or application-enforced
  seat, project, or screenshot-count caps

## Choose how to run it

| | Hosted | Self-hosted |
| --- | --- | --- |
| Best for | Starting immediately | Keeping Screenote inside your VPN or infrastructure |
| Operations | Managed at [screenote.ai](https://screenote.ai) | Kamal, one application server, and one durable volume |
| Screenshot storage | Managed | Local by default; S3-compatible storage is optional |
| Product caps | SaaS plan applies | No application-enforced seat, project, or screenshot-count caps |
| Setup | Create an account | Claim the instance once, then invite teammates |

Screenote is **source-available and self-hostable** under the
[O'Saasy License Agreement](LICENSE). It is not distributed under an
OSI-approved open-source license.

## Self-host Screenote

> [!IMPORTANT]
> The first supported source release is still being prepared. Until a version
> appears on [GitHub Releases](https://github.com/ivankuznetsov/screenote/releases),
> treat deployment from this repository as a development preview.

Screenote ships with a [Kamal](https://kamal-deploy.org/) starter configuration.
It runs the Rails application, background jobs, four SQLite databases, and
local screenshot files as one small deployment with one durable volume. Kamal
Proxy handles HTTPS. PostgreSQL, Redis, a separate worker, and a mail server
are not required.

You need a Linux AMD64 server reachable over SSH, a hostname pointed at it,
Docker with Buildx on the machine from which you deploy, and Ruby/Bundler for
this repository.

### 1. Fork and prepare Screenote

Fork this repository so your non-secret deployment settings have a stable
home. Pin the fork to an exact supported Screenote release and keep the
application source and container build unchanged; the first release supports
configuration-only deployment forks, not application-code modifications or
custom images. Replace `vX.Y.Z` below with the exact tag named by the GitHub
release. Clone that tag from the canonical repository, keep it as `upstream`,
then point `origin` at your fork:

```sh
git clone --branch vX.Y.Z https://github.com/ivankuznetsov/screenote.git
cd screenote
git remote rename origin upstream
git remote add origin https://github.com/YOUR-TEAM/screenote.git
git switch --create screenote-deploy
bin/setup --skip-server
```

For development-preview evaluation before the first release exists, clone the
moving default branch without `--branch`; that is not a supported deployment.

### 2. Configure your server

Edit `config/deploy.yml`. Replace `screenote.example.com` with the server's SSH
hostname and your public Screenote hostname, and change `ssh.user` if you do
not connect as `root`.

Copy the ignored secrets template:

```sh
cp .kamal/secrets.example .kamal/secrets
chmod 0600 .kamal/secrets
```

Generate `SECRET_KEY_BASE` with `bin/rails secret`, generate the one-time
`SCREENOTE_BOOTSTRAP_TOKEN` with `openssl rand -hex 32`, and paste each result
into `.kamal/secrets`. Never commit that file.

### 3. Deploy and claim the instance

```sh
bin/kamal setup
```

That is the supported release command—there is no separate Compose path. From
a tagged release, the repository wrapper validates the immutable GitHub
Release `public-evidence.json`, mirrors the exact qualified Screenote image
into Kamal's loopback registry, and asks Kamal to pull it without rebuilding.
The cached evidence is non-secret and ignored under `.kamal/releases/`.

Open `https://your-screenote-host/bootstrap`, enter the bootstrap token, and
create the instance administrator. Then remove `SCREENOTE_BOOTSTRAP_TOKEN`
from both `env.secret` in `config/deploy.yml` and `.kamal/secrets`, and run
`bin/kamal deploy` once more.

### 4. Invite your team

Create a project, open **Members**, and invite each collaborator. Email is
optional: without it, Screenote shows a private invitation link or manual code
you can share through a trusted channel. To send invitations automatically,
connect an external transactional provider such as Resend or Postmark through
the generic SMTP settings in `config/deploy.yml`; Screenote does not run an
SMTP server.

### 5. Deploy future changes

Replace `vNEXT` with the exact next supported tag from GitHub Releases, review
the merge, and deploy it:

```sh
git fetch upstream tag vNEXT
git merge --no-ff vNEXT
bin/setup --skip-server
bin/kamal deploy
```

The wrapper accepts configuration-only deployment branches and verifies every
release against the exact source tag and image digest. A checkout with no
supported release tag reachable in its ancestry is a development preview and
builds the working tree with a warning. If you intentionally maintain
application-code changes, set
`SCREENOTE_KAMAL_SOURCE_BUILD=1`; that custom image is outside the supported
release boundary.

Local screenshot storage is the default. S3-compatible storage is optional and
must be selected before the first deployment. Read the
[Kamal deployment guide](docs/kamal-deployment.md) for email, S3, TLS,
bootstrap cleanup, and routine operations, and the broader
[self-hosting guide](docs/self-hosting.md) for the production boundary.

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
```

Teammates resolve or reopen threads in the web review UI; agents use the CLI to
read those thread states and add replies. The CLI emits machine-readable JSON.
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
