---
title: Simple CLI installation
type: changelog
created: 2026-08-13
tags: [cli, install, release, homebrew]
---

- Replaced the hosted Go/PATH setup with a checksum-verifying `install.sh` and Homebrew tap instructions.
- Made `https://screenote.ai` the CLI's lowest-precedence default while retaining explicit self-hosted overrides.
- Reduced the hosted first run to `curl -fsSL https://screenote.ai/install.sh | sh` and `screenote login`.
- Updated `sqlite3` to 2.9.6 after the same-day advisory database flagged the locked 2.9.5 build.
- Updated Brakeman to 8.0.6 to keep the repository's scanner-freshness gate current.
