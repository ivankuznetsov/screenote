# Internal Compose harness: secrets and modes

> [!WARNING]
> This page documents Screenote's internal pre-release Docker Compose
> qualification harness. It is not the public ONCE operator workflow. Use
> [Deploy Screenote with ONCE](../once-deployment.md) and the
> [self-hosting guide](../self-hosting.md) instead.

This qualification harness reads runtime secrets from restricted files. It
keeps secret values out of `.env`, Compose environment entries, command
arguments, and the image, and mounts only paths below `/run/secrets`.

The container runs as UID/GID `1000:1000`. Compose file-backed secrets retain
their host ownership on common Docker Compose installations, so every source
file must be owned by UID 1000 and must grant no group or other permissions.
The entrypoint rejects missing files, symlinks, empty files, wrong ownership,
and broad permissions before Rails starts.

## Prepare the files

Copy `.env.self-hosted.example` to `.env`, set the immutable release image and
canonical base URL, then create the secret directory:

```sh
install -d -m 0700 secrets
umask 077
openssl rand -base64 48 > secrets/secret_key_base
chmod 0400 secrets/secret_key_base
chown 1000:1000 secrets/secret_key_base
```

The generated value exceeds the 256-bit minimum. Keep an operator-controlled,
encrypted copy of the application secret outside the Docker host; losing it
invalidates encrypted application state.

## Start a fresh local-storage instance

The same base configuration serves both fresh and claimed installations:

```sh
docker compose -f compose.yaml config
docker compose -f compose.yaml up -d
```

Open the instance in a browser to finish setup. The first completed setup
creates the administrator; the claimed installation identity is then stored in
the primary SQLite database. No temporary setup credential, overlay, or
container replacement is required.

## Use generic S3-compatible storage

S3 mode keeps all four SQLite roles on the one named volume and stores blobs
under one dedicated private bucket/prefix. Fill in the non-secret S3 settings
and credential-file paths in `.env`, then copy the dedicated credentials issued
by your provider into those files:

```sh
install -o 1000 -g 1000 -m 0400 /secure/provider/access-key-id secrets/s3_access_key_id
install -o 1000 -g 1000 -m 0400 /secure/provider/secret-access-key secrets/s3_secret_access_key
```

For an S3-backed installation, use the base and S3 files from the first start:

```sh
docker compose \
  -f compose.yaml \
  -f compose.s3.yaml \
  config
docker compose \
  -f compose.yaml \
  -f compose.s3.yaml \
  up -d
```

`compose.s3.yaml` requires the endpoint, region, bucket, prefix, and the two
credential-file paths. It also makes path-style addressing, request timeout,
retry count, request-checksum calculation, and response-checksum validation
explicit. Use `when_required` for the checksum settings only when a compatible
provider does not implement optional S3 checksums. Changing credentials while
keeping the same endpoint, region, bucket, prefix, and path-style setting is a
supported rotation. Changing that namespace after data exists requires a
storage migration and is not supported by the first release.

## Enable other optional providers

Each optional provider has its own additive overlay, so an operator mounts only
the credentials that the selected runtime needs:

| Provider | Compose overlay | File-backed credential |
|---|---|---|
| SMTP | `compose.smtp.yaml` | `SMTP_PASSWORD_FILE` |
| Google sign-in | `compose.google-oauth.yaml` | `GOOGLE_CLIENT_SECRET_FILE` |
| GitHub sign-in | `compose.github-oauth.yaml` | `GITHUB_CLIENT_SECRET_FILE` |
| Honeybadger | `compose.honeybadger.yaml` | `HONEYBADGER_API_KEY_FILE` |

Put only non-secret hostnames, ports, client IDs, sender addresses, feature
settings, and secret *paths* in `.env`. Copy each provider-issued secret to the
corresponding path from `.env`, then apply UID 1000 and mode `0400` as shown for
the S3 credentials. Never put the password, client secret, or API key itself in
`.env`.

Compose overlays can be combined. For example, this claimed local-storage
instance enables SMTP, Google, and Honeybadger without exposing any credential
as a Compose environment value:

```sh
docker compose \
  -f compose.yaml \
  -f compose.smtp.yaml \
  -f compose.google-oauth.yaml \
  -f compose.honeybadger.yaml \
  config
docker compose \
  -f compose.yaml \
  -f compose.smtp.yaml \
  -f compose.google-oauth.yaml \
  -f compose.honeybadger.yaml \
  up -d
```

Add `compose.s3.yaml` when using S3-compatible storage. GitHub sign-in uses
`compose.github-oauth.yaml`. A partially configured selected provider fails at
Compose interpolation or application boot rather than silently starting
without it.

## Rotate secrets

Stop the service, replace one file atomically with the same UID and mode, and
recreate the container. Never edit a mounted secret in place. The example below
shows the base-only mode; use the same complete `-f` overlay list that enables
your active storage and providers:

```sh
docker compose down
umask 077
openssl rand -base64 48 > secrets/secret_key_base.next
chmod 0400 secrets/secret_key_base.next
chown 1000:1000 secrets/secret_key_base.next
mv secrets/secret_key_base.next secrets/secret_key_base
docker compose up -d --force-recreate
```

Rotate a provider credential with the same overlay used to enable it. Rotate S3
credentials with the base and S3 Compose files. The application secret has
application-level consequences; take the documented whole-instance backup
before rotating it.

### Preserve active authentication links during application-secret rotation

Changing `SECRET_KEY_BASE` changes the derivation key used by invitation,
password-reset, magic-link, confirmation, and recovery links. Take a complete
backup first. Before replacing the old application-secret file, derive the old
authentication-link key into a separate restricted JSON keyring. The command
below reads the old secret from a file; it does not place the value in an
argument or environment variable:

```sh
umask 077
SCREENOTE_OLD_SECRET_KEY_BASE_PATH="$PWD/secrets/secret_key_base" \
  ruby -rbase64 -rjson -ropenssl -rdigest -e '
    secret = File.binread(ENV.fetch("SCREENOTE_OLD_SECRET_KEY_BASE_PATH")).delete_suffix("\n")
    abort "invalid application secret" if secret.bytesize < 32 || secret.include?("\n")
    key = OpenSSL::HMAC.digest("SHA256", secret, "screenote.authentication-links.keyring/v1")
    id_digest = Digest::SHA256.digest("screenote.authentication-links.key-id/v1\0".b + key)
    id = "v1.#{Base64.urlsafe_encode64(id_digest, padding: false)}"
    puts JSON.generate(id => Base64.urlsafe_encode64(key, padding: false))
  ' > secrets/authentication_link_prior_keys.next
chmod 0400 secrets/authentication_link_prior_keys.next
chown 1000:1000 secrets/authentication_link_prior_keys.next
mv secrets/authentication_link_prior_keys.next secrets/authentication_link_prior_keys
```

Treat that JSON file as an application secret. Rotate `secret_key_base`
atomically, set `SCREENOTE_AUTHENTICATION_LINK_PRIOR_KEYS_PATH`, and recreate
the container with the additive overlay:

```sh
docker compose \
  -f compose.yaml \
  -f compose.auth-link-key-rotation.yaml \
  up -d --force-recreate
```

Startup fails closed if any active link refers to a key that is absent. Keep
the overlay and prior-key file in every backup until all links using that key
have expired, been consumed, or been superseded. Then verify that no active
token uses the prior key before removing the overlay and file:

```sh
docker compose \
  -f compose.yaml \
  -f compose.auth-link-key-rotation.yaml \
  exec screenote ./bin/rails runner \
  'abort "active prior-key links remain" if AuthenticationToken.active.where.not(derivation_key_id: AuthenticationLinks::Runtime.keyring.primary_key_id).exists?'
docker compose -f compose.yaml up -d --force-recreate
rm secrets/authentication_link_prior_keys
```

Include every other active Compose overlay in these commands. An emergency
rotation requires superseding and reissuing outstanding links before the
compromised key is removed; merely omitting the prior key intentionally makes
those links unusable.

## Health and request limits

`GET /up` is process liveness only. Compose checks `GET /ready`, which returns
only `ready` or `not_ready`. Readiness verifies the primary, cache, queue, and
cable schemas, proves the persistent volume is writable, and loads the selected
Active Storage configuration without calling storage, SMTP, OAuth, or
monitoring providers. The response does not expose a failing component, path,
configuration value, or exception. Detailed external-provider reachability is
deliberately a separate diagnostic concern rather than a Compose health gate.

Thruster rejects request bodies larger than 31,457,280 bytes (30 MiB). This
preserves the existing 28 MiB MCP base64 JSON contract plus bounded envelope
overhead while preventing an unlimited body from reaching Rails.
