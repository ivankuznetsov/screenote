# Snapshot Page identity

Snapshot ingestion now preserves the product hierarchy: a Page is one stable
logical screen, a Snapshot is one capture run, and that run may add only one
Screenshot version to a Page. Manifest preparation rejects multiple screenshot
groups under the same case-insensitive Page name, while exact replay of an
already-stored legacy manifest remains available.

Preparation checks the identity again after Page resolution, closing
database-specific `LOWER()` differences, and replay uses the same lowercase
identity as admission. The MCP upload tool publishes the rule in its agent
metadata and maps a Snapshot deletion race to its stable missing-Snapshot
argument error.

The Screenshot model applies the same guard to MCP, direct application writes,
and later identity assignments. Those checks serialize on the Snapshot. Public
help and model/API wiki pages now distinguish Page identity, version history
across runs, and viewport children within a version. Historical malformed rows
still require an explicit repair before a database unique index can safely
enforce the invariant against raw SQL.
