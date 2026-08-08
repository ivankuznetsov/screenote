# Deploy Screenote with Kamal

[Kamal](https://kamal-deploy.org/) prepares a Linux server, runs Screenote, and
puts Kamal Proxy in front of it. This repository contains a self-hosted starter
at `config/deploy.yml`, an ignored secrets template at
`.kamal/secrets.example`, and a release-aware `bin/kamal` wrapper.

> [!IMPORTANT]
> The first supported source release is still being prepared. Until a version
> appears on [GitHub Releases](https://github.com/ivankuznetsov/screenote/releases),
> treat deployment from this repository as a development preview.

The setup is:

1. Fork and clone Screenote.
2. Prepare the repository.
3. Edit `config/deploy.yml` and `.kamal/secrets`.
4. Run `bin/kamal setup`.
5. Claim the instance and invite the team.

## Fork and prepare the repository

Create a GitHub fork for your team's deployment. This gives non-secret
configuration a stable home and lets you pin and review exact supported
Screenote releases. For the first supported release, keep application source
and the container build unchanged; application-code modifications and custom
images are outside the support boundary. Replace `vX.Y.Z` with the exact tag
named by the GitHub release. Clone that tag from the canonical repository,
keep it as `upstream`, then point `origin` at your fork:

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

The deployment machine needs the repository's Ruby version and Bundler, plus
Docker with Buildx for mirroring the release image through Kamal's loopback
registry. The supported first-release target is a Linux AMD64 server reachable
over SSH. Point the Screenote hostname at that server before asking Kamal Proxy
to obtain an HTTPS certificate.

## Edit the deployment configuration

Open `config/deploy.yml`. The required team-specific settings are grouped near
the top:

- `servers.web` — replace `screenote.example.com` with the server Kamal can
  reach over SSH;
- `ssh.user` — leave `root` or set the account you use for SSH;
- `proxy.host` — set the public Screenote hostname;
- `env.clear.SCREENOTE_BASE_URL` — set the complete public origin, such as
  `https://screenote.example.com`.

Keep `proxy.forward_headers: false`, `THRUSTER_FORWARD_HEADERS: true`, and the
starter's `SCREENOTE_TRUSTED_PROXIES` value together. At the internet or VPN
edge, Kamal Proxy discards client-supplied forwarding values and generates
authoritative ones. Thruster forwards those values to Rails over container
loopback. Rails trusts only that loopback hop and Kamal's private Docker-network
hop; neither application port is published directly.

With `proxy.ssl: true`, Kamal Proxy manages HTTPS for a hostname that resolves
to the server and is reachable on ports 80 and 443. For an HTTP-only private
VPN deployment, set `proxy.ssl: false` and use the matching `http://` base URL.
Use that mode only when the VPN is the accepted transport-security boundary.

Commit the non-secret `config/deploy.yml` changes to your fork.
Keep this supported starter as literal YAML: the release-aware wrapper rejects
ERB because it could change the deployment command or exact-image contract
after validation.

## Create the secrets file

Copy the tracked template to Kamal's ignored secrets file:

```sh
cp .kamal/secrets.example .kamal/secrets
chmod 0600 .kamal/secrets
```

Generate the two first-deployment values:

```sh
bin/rails secret
openssl rand -hex 32
```

Paste the first output after `SECRET_KEY_BASE=` and the second after
`SCREENOTE_BOOTSTRAP_TOKEN=` in `.kamal/secrets`.

`SECRET_KEY_BASE` protects application state. Store a protected recovery copy
outside the Screenote server and its data volume. The bootstrap token is used
once to establish the instance administrator. Do not commit `.kamal/secrets`,
paste either value into chat or an issue, or expose the file in build output.
Kamal can also read values from a password manager; see its
[secrets documentation](https://kamal-deploy.org/docs/configuration/environment-variables/#secrets).

## Deploy Screenote

Run the first deployment from the repository:

```sh
bin/kamal setup
```

For a supported tag, `bin/kamal` finds that tag beneath your configuration-only
deployment branch, downloads the immutable release's `public-evidence.json`
asset, and verifies the source revision, image manifest, OCI labels, and runtime
qualification records. It then uses Docker Buildx to copy that exact
multi-platform manifest into Kamal's loopback registry without rebuilding it.
Kamal installs Docker on the target when needed, pulls and starts the qualified
AMD64 image, creates the durable `screenote_storage` volume, starts Kamal
Proxy, and waits for `/ready`. The evidence cache under `.kamal/releases/` is
non-secret and ignored by Git.

A checkout with no supported release tag reachable in its ancestry remains a
development preview: the same command prints a warning and lets Kamal build
the working tree. After releases exist, a branch with application-code changes
fails closed. To deliberately build a customized, unsupported image, opt in
explicitly:

```sh
SCREENOTE_KAMAL_SOURCE_BUILD=1 bin/kamal setup
```

This escape hatch changes the artifact being deployed and therefore does not
carry the release image's qualification, SBOM, provenance, or support claim.

Open `<SCREENOTE_BASE_URL>/bootstrap`, enter the bootstrap token, and create the
instance administrator. Then:

1. Remove `SCREENOTE_BOOTSTRAP_TOKEN` from `env.secret` in
   `config/deploy.yml`.
2. Remove its value from `.kamal/secrets`.
3. Run `bin/kamal deploy` once more.

The claimed state lives in the primary database and cannot be reopened by
removing the token.

Create a project, open **Members**, and invite your team. Without email,
Screenote displays a private invitation link and manual code to share through
a trusted channel.

## Use external transactional email

Email is optional, and Screenote does not run a mail server. To send
invitations automatically, use an external transactional service with SMTP,
such as Resend, Postmark, SendGrid, or an equivalent provider.

In `config/deploy.yml`:

1. Set `SCREENOTE_SMTP_ENABLED` to `true`.
2. Uncomment `SMTP_USERNAME` and `SMTP_PASSWORD` in `env.secret`.
3. Set the SMTP address, port, authentication method, STARTTLS setting, and a
   provider-verified `MAILER_FROM` address.

The file includes a commented Resend example. For Postmark or another service,
use the values from that provider's SMTP documentation. Put both credential
values in `.kamal/secrets` after `SMTP_USERNAME=` and `SMTP_PASSWORD=`, then
deploy again. Some providers, including Postmark, use a secret token as the
SMTP username, so neither value belongs in tracked `env.clear` configuration.

Screenote validates the complete email configuration at startup. When email is
disabled, no message is queued and the private invitation-link flow remains
available.

## Use S3-compatible screenshot storage

Local screenshot storage is the default. It shares the durable
`screenote_storage` volume with the four SQLite databases.

To use a dedicated private S3-compatible bucket, complete these steps before
the first `bin/kamal setup`:

1. Set `SCREENOTE_STORAGE` to `s3`.
2. Fill in `SCREENOTE_S3_ENDPOINT`, `SCREENOTE_S3_REGION`,
   `SCREENOTE_S3_BUCKET`, a stable `SCREENOTE_S3_PREFIX`, and
   `SCREENOTE_S3_PATH_STYLE` in `env.clear`.
3. Uncomment `SCREENOTE_S3_ACCESS_KEY_ID` and
   `SCREENOTE_S3_SECRET_ACCESS_KEY` in `env.secret`.
4. Put both credential values in `.kamal/secrets`.

The SQLite databases remain on the named volume. Rotating credentials for the
same bucket and prefix is supported. Moving existing screenshots to another
endpoint, bucket, or prefix is a separate storage migration.

## Operate the deployment

The starter defines convenient Kamal aliases:

```sh
bin/kamal logs
bin/kamal console
bin/kamal diagnostics
```

`/up` is process liveness. `/ready` checks the databases and writable storage
and is used by the deployment health check.

Before storing important work, configure encrypted backups for the
`screenote_storage` named volume and test a full restore. Capture a consistent,
quiesced copy of all four SQLite databases and local screenshot files. Retain
the matching configuration and application secrets separately. When using S3,
back up the dedicated bucket and prefix as part of the same recovery point.

## Deploy updates

Read the new version's release notes. Replace `vNEXT` below with that exact
supported tag, fetch it from the canonical repository, review the merge into
your deployment branch, update the local dependencies, and deploy:

```sh
git fetch upstream tag vNEXT
git merge --no-ff vNEXT
bin/setup --skip-server
bin/kamal deploy
```

Take and verify a recoverable backup before an upgrade. Follow any adjacent
upgrade or rollback requirement in that release's notes.

The wrapper fetches the new immutable evidence asset and mirrors the new exact
manifest before Kamal replaces the application container. It refuses a local
release tag that already points to another digest.

The supported release notes are authoritative for every upgrade. An ordinary
`bin/kamal deploy` assumes the release uses backward-compatible migrations. If
a release requires a stopped-process migration, its notes will provide the
explicit maintenance and rollback instructions; do not improvise a maintenance
sequence from this general guide.

## Connect the CLI and agent skill

Install the tested version of the
[Screenote CLI](https://github.com/ivankuznetsov/screenote-cli) named by the
Screenote release, sign in against your `SCREENOTE_BASE_URL`, and select a
project. For coding agents, install the
[Screenote agent plugin](https://github.com/ivankuznetsov/agent-plugins/tree/main/plugins/screenote).
The plugin teaches the capture and feedback workflow while the CLI remains the
machine-readable integration boundary.

See the [self-hosting guide](self-hosting.md) for the production boundary,
[SUPPORT.md](../SUPPORT.md) for support, and [SECURITY.md](../SECURITY.md) for
private vulnerability reporting.
