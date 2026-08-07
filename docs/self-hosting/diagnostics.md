# Self-hosted diagnostics

Compose uses generic `GET /ready` checks that do not contact optional external
providers or reveal component details. Run the local operator diagnostic with
the same complete Compose file list when readiness or a provider fails:

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
keeping credentials in their restricted files. The initial supported host
contract requires UID/GID 1000 bind ownership and does not cover rootless
Docker or user-namespace remapping.
