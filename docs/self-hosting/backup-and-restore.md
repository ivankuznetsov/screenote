# Internal Compose harness: backup and restore

> [!WARNING]
> This page documents Screenote's internal pre-release Docker Compose
> qualification harness. It is not a supported operator workflow for Kamal
> deployments. Use [Deploy Screenote with Kamal](../kamal-deployment.md) and
> the [self-hosting guide](../self-hosting.md) instead.

Within this internal harness, `bin/self-host-backup` and
`bin/self-host-restore` model one stop-the-world,
origin-authenticated, age-encrypted recovery boundary for the four SQLite databases,
local volume state, external configuration, file-backed secrets, and either
local blobs or a matching S3-compatible object snapshot.

The qualification fixture uses Linux Docker Engine with the operator account,
Compose files, `.env`, secret tree, backup destination, and restore destination
owned by UID/GID `1000:1000`. Sensitive files and directories must grant no
group or other access. Run these commands as host UID 1000. Rootless Docker,
Docker user-namespace remapping, NFS/SMB volumes, and hosts that cannot preserve
UID 1000 bind-mount ownership are outside the initial support contract.

## Prepare independent recovery material

Create the age identity on a different encrypted operator-controlled system,
not on the Screenote volume or in the repository:

```sh
umask 077
age-keygen -o /secure/screenote-backup-identity.txt
age-keygen -y /secure/screenote-backup-identity.txt
```

The second command prints the public recipient. Store the identity in a
separate recovery system, owned by UID 1000 and mode `0400`. Losing it makes
the backup unrecoverable. Never copy the identity into the backup set,
application volume, container image, CI variables, or logs.

Age recipients are public, so encryption alone does not prove who created a
backup. Generate a separate random authentication key on the operator system:

```sh
umask 077
openssl rand 64 > /secure/screenote-backup-authentication-key
chmod 0400 /secure/screenote-backup-authentication-key
```

The key must be one owner-only, single-link regular file containing 32–4096
bytes. It must not be the age identity, configuration, a Compose file, a file
in `secrets/`, application data, or any backup-set member. Keep independent
escrowed copies outside the Screenote host and backup media. The same key is
required for backup and restore; losing either it or the age identity makes
the set unusable. Never put the key value in `.env`, a command-line value, CI,
the repository, the application volume, the container image, or logs. The
commands receive only its absolute file path.

### Rotate or respond to compromised recovery material

Each completed set is permanently bound to the authentication-key fingerprint
in its completion marker and to the age-recipient fingerprint in its encrypted
manifest. Rotation does not rewrite retained sets. Generate a new independent
key (and a new age identity when rotating encryption), create and drill a new
backup, then retain each old recovery factor only as long as a set that needs
it remains in policy. Retire an old set and its escrowed factors together.

If an authentication key may be exposed, treat every set made with its
fingerprint as forgeable: stop using it, generate a new key on a trusted
operator system, and create and drill a fresh backup from a trusted running
instance. If an age identity may be exposed, rotate both the age identity and
authentication key before creating the replacement set. Do not establish trust
in an old set merely because it decrypts; use separately retained incident and
provider evidence when deciding whether historical recovery data is safe.

Create an external destination that is not below the Screenote volume:

```sh
install -o 1000 -g 1000 -m 0700 -d /srv/screenote-backups
```

## Create a local-storage backup

Use the exact Compose file list that runs the instance. Every filename and
SHA-256 digest becomes part of the encrypted manifest. The image must be the
currently running immutable digest. Use `none` only for the initial release;
later release notes name the one supported adjacent predecessor.

The configuration file and a directory named exactly `secrets/` must share one
parent directory. Every selected Compose secret must use a simple
`./secrets/...` value in that configuration, and the tree must contain exactly
the regular secret files consumed by `services.screenote`—no omitted overlay
credential, stale extra file, symlink, external secret, or absolute path. Before
stopping the service, the command renders the effective Compose JSON from the
supplied `.env` under a sanitized Docker environment and proves that every
consumed top-level secret resolves to that exact archived file set. Ambient
shell variables cannot override the stored configuration during this check or
the backup run. The rendered model must also select one writable named volume
at `/rails/storage`. Before stopping, Screenote verifies that the running
container uses that exact Docker volume name and local-driver mountpoint, so a
remapped or stale data volume cannot be archived by mistake.

```sh
bin/self-host-backup \
  --destination /srv/screenote-backups/2026-08-06.screenote \
  --recipient age1REPLACE_WITH_PUBLIC_RECIPIENT \
  --authentication-key /secure/screenote-backup-authentication-key \
  --configuration "$PWD/.env" \
  --secret-bundle "$PWD/secrets" \
  --image ghcr.io/ivankuznetsov/screenote@sha256:REPLACE_WITH_DIGEST \
  --predecessor none \
  --compose-file "$PWD/compose.yaml"
```

The command verifies that the service is healthy and running the supplied
image, asks Docker to stop it gracefully, requires a clean exit, and only then
archives the complete `/rails/storage` mount. Puma stops accepting work while
its active requests and the in-Puma Solid Queue supervisor drain. If graceful
shutdown, encryption, validation, or publication fails, the command leaves the
service stopped and never presents a partial directory as complete. Inspect
the failure before manually restarting.

On success the directory is mode `0700`; every file is mode `0600`. It contains
only age ciphertext plus a non-secret completion marker. The encrypted
manifest binds the archive bytes, configuration, protected secret bundle,
exact image and predecessor, all four database schema versions, persisted
storage identity, Compose contract, and every database-referenced blob.
The completion marker contains a domain-separated HMAC of the encrypted
manifest digest and a fingerprint of the independent authentication key.
Restore verifies that HMAC in constant time before decrypting the manifest;
the key itself is never placed in the set.
Retention and deletion are operator-controlled. Copy the complete directory
atomically; never select individual files from it.

## Add S3-compatible object evidence

S3 mode requires a provider-specific executable hook. It runs only after the
application has stopped and must create a provider-side, authenticated
age-encrypted snapshot or copy of the instance's dedicated bucket/prefix. A
versioning flag or plaintext provider snapshot is not sufficient. Configure
the hook's provider credentials outside Screenote, keep its logs free of
secrets, and make it write one final evidence file to
`SCREENOTE_S3_EVIDENCE_PATH` with UID 1000 and mode `0600`.

The hook receives these non-secret environment values:

- `SCREENOTE_BACKUP_QUIESCED_AT`
- `SCREENOTE_BACKUP_RESTORE_IMAGE`
- `SCREENOTE_BACKUP_PREDECESSOR`
- `SCREENOTE_BACKUP_AGE_RECIPIENT`
- `SCREENOTE_BACKUP_AGE_RECIPIENT_FINGERPRINT`
- `SCREENOTE_S3_EVIDENCE_PATH`

The evidence is an exact `screenote-s3-snapshot-evidence/v1` JSON object:

```json
{
  "schema": "screenote-s3-snapshot-evidence/v1",
  "status": "finalized",
  "namespace_fingerprint": "64 lowercase hex characters",
  "snapshot_reference": "provider-owned-opaque-reference",
  "snapshot_started_at": "2026-08-06T10:00:01Z",
  "snapshot_completed_at": "2026-08-06T10:02:00Z",
  "backup_quiesced_at": "2026-08-06T10:00:00Z",
  "object_set_encryption": {
    "scheme": "age",
    "recipient_fingerprint": "64 lowercase hex characters",
    "authenticated": true
  },
  "object_set_sha256": "64 lowercase hex characters",
  "objects": []
}
```

`objects` must contain exactly every blob referenced by the primary database,
sorted by `service` then `key`, with each object using keys in this exact order:
`service`, `key`, `byte_size`, `checksum`, `version`. `version` is an immutable
provider version or checksum for the copied ciphertext. `object_set_sha256` is
SHA-256 of the compact UTF-8 JSON encoding of that canonical array. The local
backup command verifies the time boundary, namespace, recipient fingerprint,
canonical digest, uniqueness, and equality with the database inventory. This
contract records what the provider hook proved; Screenote cannot independently
certify a provider-side copy, so the hook and provider recovery drill remain
part of the operator's trust boundary.

Supply both S3 options in addition to the local command:

```sh
  --s3-snapshot-command /secure/bin/screenote-s3-snapshot \
  --s3-evidence /srv/screenote-backups/s3-evidence.json
```

The evidence path must not already exist. The completed local backup contains
an authenticated encrypted copy of the evidence; the plaintext hook output may
then be retained or securely removed according to the operator's policy.

## Restore without overwriting data

Download the exact immutable image before the outage window. Prepare an empty,
restricted operator directory. The named Docker volume may be absent or must
be empty; the command never empties or overwrites it.

```sh
docker pull ghcr.io/ivankuznetsov/screenote@sha256:REPLACE_WITH_DIGEST
install -o 1000 -g 1000 -m 0700 -d /srv/screenote-restore/operator

bin/self-host-restore \
  --source /srv/screenote-backups/2026-08-06.screenote \
  --identity /secure/screenote-backup-identity.txt \
  --authentication-key /secure/screenote-backup-authentication-key \
  --target-volume screenote_restore_20260806 \
  --operator-destination /srv/screenote-restore/operator \
  --image ghcr.io/ivankuznetsov/screenote@sha256:REPLACE_WITH_DIGEST \
  --predecessor none \
  --compose-file "$PWD/compose.yaml"
```

Restore authenticates the completion marker on the host before creating or
changing a target volume or stopping a current service. The isolated restore
container snapshots every external input into private staging, repeats that
authentication to close input races, validates the exact file set and
manifest, extracts only regular files and
directories, verifies all four SQLite databases with `integrity_check` and
`foreign_key_check`, checks schema/storage/blob identity, and publishes only
after all validation succeeds. It then re-renders Compose from the restored
`.env` and restored `secrets/` with the same sanitized-environment and exact
consumed-file contract. Only after that passes does it start a one-shot verifier
in the exact recorded image. That verifier checks each database again,
downloads every original local/S3 object to verify size and checksum, preflights
the authentication-link keyring, releases stale claimed queue work, and
schedules idempotent screenshot processing reconciliation. Only then does
Compose start the restored service.

For S3, restore the provider-side encrypted object set named by the evidence
into the configured dedicated bucket/prefix before running the Screenote
restore. Do not point the restored databases at a different namespace. Runtime
verification fails before service start if any original object is absent or
changed.

The original Docker volume is never modified. The restored `.env` and
`secrets/` appear under the operator destination, which becomes the Compose
project directory. A failed validation keeps the new target stopped. If a
filesystem failure prevents publication rollback, a
`.screenote-restore-failed` marker guards the target for manual inspection.

## Stable exit codes

| Code | Meaning |
|---:|---|
| 0 | Operation completed and verified |
| 64 | Missing or invalid command arguments |
| 65 | Invalid, unauthenticated, mismatched, or corrupt recovery data |
| 69 | Required command or selected provider is unavailable |
| 70 | Docker or an unexpected operation failed |
| 73 | Unsafe state, path, image, existing output, or nonempty target |
| 74 | Local filesystem publication failed |
| 75 | Graceful stop, provider snapshot, archive, or restart failed |
| 78 | Unsupported host UID or ownership/permission contract |

Commands redact secret values and provider errors. Preserve the stopped state
and the original data when investigating a nonzero result.

## Recovery drills

At least quarterly and before each upgrade, restore the newest set into a new
volume on an isolated host, verify sign-in, projects, screenshots, annotations,
comments, and pending work, then remove only the drill resources by their exact
names. A backup that has not completed a restore drill is not proven recovery.
