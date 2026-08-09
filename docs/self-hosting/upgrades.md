# Internal Compose harness: upgrades and rollback

> [!WARNING]
> This page documents Screenote's internal pre-release Docker Compose
> qualification harness. It is not the public ONCE operator workflow. Use
> [Deploy Screenote with ONCE](../once-deployment.md) and the
> [self-hosting guide](../self-hosting.md) instead.

The qualification harness models sequential upgrades between adjacent
published releases with immutable image digests. It must not skip intermediate
releases or run predecessor code against state touched by its successor.

## Upgrade one adjacent release

1. Read both releases' notes for storage, configuration, and irreversible
   migration changes. Pull the successor by immutable digest.
2. Create and drill a complete backup with `bin/self-host-backup` and the
   predecessor declaration required by the successor's release notes. The
   backup moment is the rollback boundary; later writes will be lost on
   rollback.
3. Keep the predecessor image digest, age identity, independent backup
   authentication key, backup directory, original Compose files, external
   configuration, secrets, and S3 snapshot available.
4. Change only `SCREENOTE_IMAGE` to the successor digest, preserve the same
   complete overlay list, run `docker compose config`, then recreate the
   service.
5. Wait for `/ready`, run `bin/self-host-diagnostics`, and verify sign-in,
   projects, screenshots, annotations, comments, invitations, and queued image
   processing before reopening normal access.

The repository's initial source-available release has predecessor `none` and
supports only same-image backup/restore. Later releases must ship an adjacent
predecessor fixture and test that exact pair before publication.

## Roll back as whole-instance recovery

If successor verification fails, stop it. Do not merely change the image back:
the successor may already have migrated durable state.

Restore the exact pre-upgrade backup into a new empty Docker volume and empty
operator destination with `bin/self-host-restore`, supplying the predecessor's
retained immutable image and the exact predecessor declaration recorded by the
set. For S3, first restore the matching provider-side encrypted object set.
Only the restore verifier may start the predecessor. After verification,
switch traffic to the restored instance and retain the failed successor volume
for diagnosis.

Rollback discards every write after the backup boundary. Never use
`docker compose down --volumes`, delete SQLite WAL files, hot-copy individual
databases, restore selected objects, or attach an older image to migrated
state.

Credential-hardening releases may declare a dedicated stopped-process cutover
instead of an ordinary rolling deploy. Follow that release's cutover command;
normal deployment fails closed while such a migration is pending.
