# Internal Compose harness: diagnostics

> [!WARNING]
> This page documents Screenote's internal pre-release Docker Compose
> qualification harness. It is not a supported operator workflow for Kamal
> deployments. Use [Deploy Screenote with Kamal](../kamal-deployment.md) and
> the [self-hosting guide](../self-hosting.md) instead.

The Compose qualification harness uses generic `GET /ready` checks that do not
contact optional external providers or reveal component details. Its diagnostic
fixture uses the same complete Compose file list:

```sh
bin/self-host-diagnostics \
  --compose-file "$PWD/compose.yaml" \
  --project-name screenote
```

The command must run as host UID 1000. It executes inside the running service
and returns redacted JSON covering all four database roles, volume
writability, selected local/S3 object-storage round trip, and configured SMTP,
OAuth, and monitoring profiles. It reports stable `ok`, `disabled`, or
`unavailable` states without paths, credential values, endpoints, object keys,
exception text, or provider response bodies. Exit `0` means all required checks
passed; exit `69` means a required diagnostic failed.

Provider failure does not make `/ready` restart an otherwise healthy offline
core. Use the detailed result to test the selected provider from the host while
keeping credentials in their restricted files. The harness host fixture
requires UID/GID 1000 bind ownership and does not cover rootless
Docker or user-namespace remapping.
