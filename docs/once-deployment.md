# Deploy Screenote with ONCE

[ONCE](https://github.com/basecamp/once) installs and operates compatible Docker
applications on one server. It gives Screenote a reverse proxy, HTTPS, a
durable volume, logs, settings, updates, and backups without requiring a
repository checkout or deployment fork.

> [!IMPORTANT]
> The first supported Screenote source release is still being prepared. Until
> a version appears on
> [GitHub Releases](https://github.com/ivankuznetsov/screenote/releases), treat
> deployment from this repository as a development preview.

This guide uses ONCE's official stable installer. Each Screenote release names
the exact ONCE version used for release qualification. ONCE maintains its own
application-server updates separately; `--auto-update=false` below prevents
only the Screenote image from moving without an operator-approved update.

## Prepare the server

The first Screenote release targets a Linux AMD64 server with at least 2 vCPUs,
4 GiB of RAM, and 40 GiB of free SSD storage. Point a hostname at the server
and make ports 80 and 443 reachable. Run ONCE on that server:

```sh
curl https://get.once.com | ONCE_INTERACTIVE=false sh
once version
```

The installer also installs Docker on supported systems when needed. If Docker
commands require `sudo` for your account, run every `once` command with `sudo`.
If ONCE was already installed and `once version` is older than the version named
by the Screenote release, run `sudo once self-update` and check the version
again. Re-running the installer does not replace an existing ONCE binary.

## Deploy the exact release image

Open the Screenote GitHub Release and copy its complete image reference. A
supported reference contains both the release tag and immutable manifest
digest, in the form `vX.Y.Z@sha256:...`. Do not substitute `latest`, a tag by
itself, an untagged branch, or a locally rebuilt image.

```sh
SCREENOTE_HOST=screenote.example.com
SCREENOTE_BOOTSTRAP_TOKEN="$(openssl rand -hex 32)"

once deploy \
  ghcr.io/ivankuznetsov/screenote:vX.Y.Z@sha256:REPLACE_WITH_RELEASE_DIGEST \
  --host "$SCREENOTE_HOST" \
  --auto-update=false \
  --env "SCREENOTE_BASE_URL=https://$SCREENOTE_HOST" \
  --env "SCREENOTE_BOOTSTRAP_TOKEN=$SCREENOTE_BOOTSTRAP_TOKEN"
```

ONCE generates and retains the Rails `SECRET_KEY_BASE`; do not create a second
one. Automatic application updates stay disabled so each Screenote migration
follows its release notes and exact image digest.

ONCE obtains HTTPS for a publicly resolvable hostname. For an HTTP-only private
VPN deployment, add `--disable-tls` and use the matching base URL:

```sh
--disable-tls \
--env "SCREENOTE_BASE_URL=http://screenote.internal"
```

Use HTTP only when the VPN is the trusted transport boundary. The base URL must
be one origin with no credentials, path, query, or fragment. The supported
topology sends clients directly to ONCE; do not add another reverse proxy in
front of it without separately qualifying that proxy chain.

## Claim the instance

Open `https://screenote.example.com/bootstrap`, then display and enter the
one-time token:

```sh
printf '%s\n' "$SCREENOTE_BOOTSTRAP_TOKEN"
```

Create the instance administrator. Then run `once`, select Screenote, open
**Settings → Environment**, remove `SCREENOTE_BOOTSTRAP_TOKEN`, and keep
`SCREENOTE_BASE_URL`. The administrator claim remains in the database after
the token is removed.

You can also remove the token from the command line when those are the only two
custom environment variables:

```sh
once update "$SCREENOTE_HOST" \
  --env "SCREENOTE_BASE_URL=https://$SCREENOTE_HOST"
```

`once update --env` replaces the complete custom environment map. If you have
added S3 or other custom settings, use the ONCE settings screen or repeat every
custom variable in the command. Omitting one removes it.

Create a project, open **Members**, and invite your team. Without email,
Screenote gives the project owner a private invitation link or manual code to
share through a trusted channel.

## Add email with Resend or Postmark

Screenote does not run an SMTP server. To send invitations automatically, run
`once`, select Screenote, and enter a transactional provider's values under
**Settings → Email**. Resend, Postmark, and other SMTP providers work.

ONCE supplies `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`,
and `MAILER_FROM_ADDRESS` to Screenote. Use a sender verified by the provider.
Screenote enables email when that SMTP address is present and rejects an
incomplete configuration at startup. Removing the email settings restores the
manual invitation flow.

## Use S3-compatible screenshot storage

Local storage is the default. It keeps all four SQLite databases and screenshot
files on the ONCE volume mounted at `/storage` and `/rails/storage`.

To use a private S3-compatible bucket, add these custom variables to the
initial `once deploy` command:

```sh
--env "SCREENOTE_STORAGE=s3" \
--env "SCREENOTE_S3_ENDPOINT=https://objects.example.com" \
--env "SCREENOTE_S3_REGION=region-name" \
--env "SCREENOTE_S3_BUCKET=private-bucket" \
--env "SCREENOTE_S3_PREFIX=screenote-team" \
--env "SCREENOTE_S3_ACCESS_KEY_ID=$SCREENOTE_S3_ACCESS_KEY_ID" \
--env "SCREENOTE_S3_SECRET_ACCESS_KEY=$SCREENOTE_S3_SECRET_ACCESS_KEY"
```

Set the two credential variables in the shell from your secret manager before
running the command. Add `SCREENOTE_S3_PATH_STYLE=false` only when the provider
requires virtual-hosted-style requests; the default is path-style.

Choose the bucket and stable prefix before storing screenshots. Changing
credentials for the same namespace is routine; changing the endpoint, bucket,
or prefix after uploads exist is a data migration. The SQLite databases always
remain on the ONCE volume.

## Back up and restore

Create a backup before inviting a team and before every update:

```sh
mkdir -p screenote-backups
chmod 0700 screenote-backups
once backup screenote.example.com screenote-backups/screenote-2026-08-09.tar.gz
```

The backup contains ONCE application settings and the persistent volume. With
local screenshot storage that covers the four SQLite databases and screenshots.
Screenote does not currently provide an ONCE pre-backup hook, so ONCE pauses
the container while it copies the volume to keep the backup consistent.

The archive contains private application data and retained settings, including
secrets. Store it outside the application volume, restrict access, encrypt it
at rest, and copy it off the server. Configure automatic backups from ONCE's
Backups settings if desired.

For S3 mode, the ONCE archive covers the databases and settings but not the
external bucket. Protect that bucket with provider backups or versioning and
test recovery of the volume and matching object namespace together.

Restore a backup on an isolated server first and follow the release notes for
the image recorded by that backup:

```sh
once restore screenote-backups/screenote-2026-08-09.tar.gz
```

A backup is not proven until you have restored it and verified sign-in,
projects, screenshots, annotations, comments, and pending processing.

## Update Screenote

Read every release note in sequence. Copy the next release's exact image
reference, take a verified backup, and update the application:

```sh
once backup screenote.example.com screenote-backups/screenote-before-vNEXT.tar.gz
once update screenote.example.com \
  --image ghcr.io/ivankuznetsov/screenote:vNEXT@sha256:REPLACE_WITH_RELEASE_DIGEST
```

An image-only update preserves the existing hostname, custom environment,
email, backup, and resource settings. Do not attach an older image to data that
a newer release has migrated. If a release requires maintenance or an adjacent
upgrade, its release notes are authoritative.

Run `once` for the dashboard, settings, actions, and logs. `once list` shows
installed applications; `once stop HOST`, `once start HOST`, and
`once exec HOST COMMAND` provide the corresponding command-line operations.
Screenote exposes `/up` for process liveness and `/ready` for its database and
storage readiness check.

See the [self-hosting guide](self-hosting.md) for the production boundary,
[SUPPORT.md](../SUPPORT.md) for support, and [SECURITY.md](../SECURITY.md) for
private vulnerability reporting.
