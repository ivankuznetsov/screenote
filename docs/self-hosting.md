# Self-host Screenote

The supported first-release topology is one Linux Docker container, four
SQLite databases on one durable local block-filesystem volume, and either local
or S3-compatible screenshot storage. It has no Stripe dependency, license key,
seat cap, project cap, or screenshot cap.

Use only a published release checkout and the immutable container digest named
in that release. An untagged branch, `latest`, a custom image, self-hosted
PostgreSQL, NFS/SMB storage, clustering, and high availability are not supported
by the first release.

## Minimum host

The first-release minimum profile is Linux AMD64 with 2 vCPUs, 4 GiB of RAM,
40 GiB of free local SSD storage, and host/container UID/GID `1000:1000`.
`config/release/minimum-host-v1.json` is the versioned source of truth. Every
release must run its exact candidate image on that profile with 25 independently
authenticated API sessions, four simultaneous 20 MiB uploads, and 20 comment
mutations per second for ten minutes before publication.

The tracked driver and verifier use the `screenote-load-smoke/v2` contract. The
verifier passes the full tracked profile, immutable image digest, and exact
source commit to the driver; the retained evidence identifies those inputs and
contains only numeric qualification results, never API keys or secret values.

This profile is a supported single-instance baseline, not a high-availability
or unlimited-throughput promise. Operators should provision additional storage
for retained originals, variants, backups, and normal filesystem headroom.

## Install with local screenshot storage

Install Docker Engine with the Compose plugin. Copy the release's
`compose.yaml`, `compose.bootstrap.yaml`, `.env.self-hosted.example`, and any
selected overlays into one operator directory:

```sh
cp .env.self-hosted.example .env
chmod 0600 .env
```

Edit `.env` and set `SCREENOTE_IMAGE` to the release's full
`ghcr.io/...@sha256:...` reference. Set `SCREENOTE_BASE_URL` to the one public
HTTP(S) origin users and clients will use; it cannot contain credentials, a
path, query, or fragment.

The initial supported ownership model is host and container UID/GID
`1000:1000`. Run the operational commands as UID 1000 and create restricted
secrets:

```sh
install -o 1000 -g 1000 -m 0700 -d secrets
umask 077
openssl rand -base64 48 > secrets/secret_key_base
openssl rand -base64 48 > secrets/bootstrap_token
chmod 0400 secrets/secret_key_base secrets/bootstrap_token
chown 1000:1000 secrets/secret_key_base secrets/bootstrap_token
```

Render the configuration before starting:

```sh
docker compose -f compose.yaml -f compose.bootstrap.yaml config
docker compose -f compose.yaml -f compose.bootstrap.yaml up -d --wait
```

Open `SCREENOTE_BASE_URL/bootstrap`, enter the one-time bootstrap token, and
create the instance administrator. When the claim succeeds, remove bootstrap
material and replace the container in claimed mode:

```sh
docker compose -f compose.yaml -f compose.bootstrap.yaml down
rm secrets/bootstrap_token
docker compose -f compose.yaml up -d --wait
```

Do not add `--volumes` to `down`; that option deletes the durable named volume.
The claimed instance never reopens bootstrap.

## Use S3-compatible screenshot storage

Use one dedicated private bucket and prefix. Fill in every `SCREENOTE_S3_*`
non-secret setting in `.env`, create the two UID-1000/mode-0400 credential
files, then include `compose.s3.yaml` for both bootstrap and claimed operation:

```sh
docker compose \
  -f compose.yaml \
  -f compose.bootstrap.yaml \
  -f compose.s3.yaml \
  config
docker compose \
  -f compose.yaml \
  -f compose.bootstrap.yaml \
  -f compose.s3.yaml \
  up -d --wait
```

After claim, remove the bootstrap overlay and token but retain the S3 overlay:

```sh
docker compose \
  -f compose.yaml \
  -f compose.bootstrap.yaml \
  -f compose.s3.yaml \
  down
rm secrets/bootstrap_token
docker compose -f compose.yaml -f compose.s3.yaml up -d --wait
```

Changing S3 credentials for the same endpoint, region, bucket, prefix, and
path-style setting is supported. Changing that namespace after blobs exist is
a storage migration and is not supported by the first release.

## Optional providers

Add only the overlays you use:

| Capability | Overlay |
|---|---|
| SMTP mail | `compose.smtp.yaml` |
| Google sign-in | `compose.google-oauth.yaml` |
| GitHub sign-in | `compose.github-oauth.yaml` |
| Honeybadger | `compose.honeybadger.yaml` |
| Prior authentication-link key during rotation | `compose.auth-link-key-rotation.yaml` |

Each overlay fails closed on partial configuration and mounts credentials from
restricted files. Core local review works without any optional provider.

## Reverse proxy and TLS

For production, terminate TLS at a private VPN ingress or reverse proxy, set
`SCREENOTE_BASE_URL=https://screenote.example.com`, and set
`SCREENOTE_TRUSTED_PROXIES` to only the immediate proxy IP addresses or CIDRs,
comma-separated. The proxy must preserve the host and send the original scheme
and client address using standard `Forwarded` or `X-Forwarded-*` headers.
Screenote discards those headers from untrusted peers and refuses a trust range
covering the entire internet. Restrict port 3005 so users cannot bypass the
proxy.

HTTP is suitable only for a trusted local/VPN origin where its transport risk
is accepted. The canonical origin controls generated links, host authorization,
TLS redirects, and secure cookies.

## Check and operate the instance

- `GET /up` is process liveness.
- `GET /ready` is generic, local orchestrator readiness and is the Compose
  health check.
- [Detailed diagnostics](self-hosting/diagnostics.md) probe the selected
  external providers without exposing configuration.
- [Secrets and provider overlays](self-hosting/secrets.md) cover bootstrap,
  rotation, SMTP, OAuth, Honeybadger, and S3 credentials.
- [Backup and restore](self-hosting/backup-and-restore.md) defines the encrypted
  whole-instance recovery boundary and mandatory restore drills.
- [Upgrades and rollback](self-hosting/upgrades.md) require adjacent immutable
  releases and restore-before-old-code rollback.

Run diagnostics after startup with the same overlay list:

```sh
bin/self-host-diagnostics \
  --compose-file "$PWD/compose.yaml" \
  --project-name screenote
```

Operators own host/network security, TLS, provider accounts, capacity,
monitoring, backup retention, secret recovery, and tested restores. See
[SUPPORT.md](../SUPPORT.md) for the support boundary and [SECURITY.md](../SECURITY.md)
for private vulnerability reporting.
