# Deploy Screenote with ONCE

[ONCE](https://github.com/basecamp/once) runs Screenote on one Linux server. It
installs Docker when needed and manages the HTTPS proxy, application container,
durable volume, settings, updates, backups, and logs. You do not need a source
checkout or deployment fork.

## Install

Prepare a Linux server with a 64-bit Intel/AMD (x86-64) or ARM64 processor. We
recommend at least 2 vCPUs, 4 GiB of RAM, and 40 GiB of free SSD storage. Point
your hostname at the server and allow inbound traffic on ports 80 and 443.

Install released stock ONCE, then deploy Screenote with the hostname and its
matching canonical URL:

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

The stock installer installs Docker when needed. `once deploy` keeps automatic
Screenote updates enabled and stores the application data on one durable
volume.

Open the hostname as soon as installation finishes and create the first
administrator. The first person to complete this form claims the fresh
instance; a database lock makes concurrent claims single-winner. After that,
account creation is invitation-only.

Create a project, open **Members**, and invite your team. Without email,
Screenote provides a private invitation link or manual code to share through a
trusted channel.

## Canonical URL

`SCREENOTE_BASE_URL` is required and must use the same hostname and scheme as
the ONCE deployment. Screenote uses it for allowed hosts, generated links,
redirects, OAuth callbacks, HTTPS enforcement, and secure cookies. Keep the two
values identical; otherwise host authorization or generated URLs will not
match the deployed application. No administrator setup credential is required:
the first visitor claims a fresh instance atomically.

## Add email with Resend or Postmark

Screenote does not run a mail server. To send invitations automatically, run
`once`, select Screenote, then enter a transactional provider's values under
**Settings → Email**. Resend, Postmark, and other SMTP providers work.

ONCE supplies the SMTP server, port, username, password, and sender address.
Use a sender verified by the provider. Removing the email settings returns
Screenote to the manual invitation flow.

## HTTP or S3 first deployment

The simple deployment uses HTTPS and local screenshot storage. If the first
boot must instead use HTTP inside a trusted VPN or a private S3-compatible
bucket, include those settings in the initial `once deploy` command.

For an HTTP-only private hostname:

```sh
once deploy ghcr.io/ivankuznetsov/screenote:latest \
  --host screenote.internal \
  --disable-tls \
  --env SCREENOTE_BASE_URL=http://screenote.internal
```

Use HTTP only when the VPN is the trusted transport boundary. The supported
topology sends clients directly to ONCE; an additional reverse proxy requires
separate qualification.

For S3-compatible screenshot storage, export the credentials from your secret
manager and deploy with the complete storage namespace:

```sh
export SCREENOTE_S3_ACCESS_KEY_ID=replace-me
export SCREENOTE_S3_SECRET_ACCESS_KEY=replace-me

once deploy ghcr.io/ivankuznetsov/screenote:latest \
  --host screenote.example.com \
  --env SCREENOTE_BASE_URL=https://screenote.example.com \
  --env "SCREENOTE_STORAGE=s3" \
  --env "SCREENOTE_S3_ENDPOINT=https://objects.example.com" \
  --env "SCREENOTE_S3_REGION=region-name" \
  --env "SCREENOTE_S3_BUCKET=private-bucket" \
  --env "SCREENOTE_S3_PREFIX=screenote-team" \
  --env "SCREENOTE_S3_ACCESS_KEY_ID=$SCREENOTE_S3_ACCESS_KEY_ID" \
  --env "SCREENOTE_S3_SECRET_ACCESS_KEY=$SCREENOTE_S3_SECRET_ACCESS_KEY"
```

Add `SCREENOTE_S3_PATH_STYLE=false` only when the provider requires
virtual-hosted-style requests; path-style is the default. Choose the service,
bucket, and stable prefix before the first boot. Changing credentials for the
same namespace is routine; changing between local and S3 or changing the
endpoint, bucket, or prefix later is a data migration. The four SQLite
databases always remain on the ONCE volume.

## Back up and restore

Configure automatic backups from ONCE's **Backups** settings. You can also
create one immediately:

```sh
mkdir -p screenote-backups
chmod 0700 screenote-backups
once backup screenote.example.com screenote-backups/screenote-2026-08-10.tar.gz
```

ONCE pauses Screenote while copying the application settings and durable volume
so the four SQLite databases stay consistent. With local screenshot storage,
the archive also contains the screenshots. It contains private application
data and retained settings, so restrict access, encrypt it at rest, and copy it
off the server.

With S3 storage, the ONCE archive does not contain the external bucket. Protect
that bucket separately and recover it to the same point as the databases.

Test restores on an isolated server:

```sh
once restore screenote-backups/screenote-2026-08-10.tar.gz
```

Verify sign-in, projects, screenshots, annotations, comments, invitations, and
pending processing. A backup is not proven until its restore has been tested.

The normal installation records the moving `latest` image name, so a restore
pulls the current release. If your recovery policy requires a version-pinned
rollback, use the immutable image reference published in GitHub Releases.

## Updates and operations

ONCE automatically checks for and applies Screenote updates. To apply the
latest release immediately, take a backup and run:

```sh
once update screenote.example.com
```

The update preserves the hostname, custom environment, email, backup, and
resource settings. Release notes remain authoritative when an update requires
special maintenance.

Run `once` for the dashboard, settings, actions, and logs. `once list` shows
installed applications, while `once stop HOST` and `once start HOST` control an
application from the command line. Screenote exposes `/up` for process
liveness and `/ready` for database and storage readiness.

See the [self-hosting guide](self-hosting.md) for the production boundary,
[SUPPORT.md](../SUPPORT.md) for support, and [SECURITY.md](../SECURITY.md) for
private vulnerability reporting. Each Screenote release records the exact ONCE
version and immutable image digest used for release qualification.
