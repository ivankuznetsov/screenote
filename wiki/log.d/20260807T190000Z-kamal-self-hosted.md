---
date: 2026-08-07
type: decision
pages: [self-hosting, api-cli, architecture, active-areas, gaps]
---

Made Kamal the public self-hosted deployment path, following Fizzy's
Rails-style fork/configure/setup workflow. `config/deploy.yml` is now the
self-host starter; the hosted service moved to isolated
`config/deploy.saas.yml` with SaaS-only hooks. Public agent positioning is CLI
plus the Screenote agent skill, and external mail is provided through generic
SMTP services such as Resend or Postmark rather than a bundled mail container.
The remaining Compose-specific backup/restore harness is recorded as a release
gap instead of being presented in the README.

Review hardened that boundary: the edge proxy now discards caller-supplied
forwarding headers, Kamal bridges fingerprinted assets across replacements,
the entrypoint keeps `/rails/storage` immutable, configuration-only
release-pinned forks are distinguished from unsupported application forks,
and legacy Compose guides are explicitly marked as internal. The public CLI
example no longer claims annotation resolution that the released CLI/plugin
does not expose. Ordinary Kamal deploys assume backward-compatible migrations;
stopped-process migrations remain a release-qualified upgrade responsibility.
Supported setup now clones the exact release tag rather than a moving branch,
the starter names Linux AMD64 as its first-release target, and optional SMTP
username/password values both stay in ignored Kamal secrets. Contributor docs
use the manifest-backed self-hosted matrix instead of booting SaaS-only tests
under the self-hosted route set.
The load-driver timeout regression now records the spawned process at the
signal boundary instead of requiring the child to write a PID file before a
sub-second deadline, removing a parallel-suite scheduling race while retaining
the kill-and-reap assertion.
The final documentation pass also made the architecture page edition-aware,
replaced legacy MCP expansion language with CLI/plugin release parity, added
bootstrap-token cleanup to the README quick start, and made updates fetch and
merge an exact canonical release tag.
The supported clone flow reads release tags from the canonical repository
because GitHub forks do not copy upstream tag refs. The proxy contract also
accounts for both private hops: Kamal Proxy sanitizes edge headers, Thruster
forwards them over loopback, and Rails trusts the loopback plus Kamal's Docker
network so HTTPS and client identity survive without trusting public input.
The supported commands remain `bin/kamal setup` and `bin/kamal deploy`, but a
published release now takes an exact-image path: the wrapper validates the
immutable public evidence asset, mirrors the qualified parent manifest through
Kamal's loopback registry without rebuilding, and lets Kamal pull it under the
source SHA. Release images carry Kamal's required service label, qualification
checks the release labels, configuration-only forks fail closed on application
divergence, and checkouts with no reachable release tag or explicitly opted-in
source builds are identified as development/custom images. A real-parser
regression also corrected the hosted wrapper and deploy guard: Kamal command
options must follow the top-level command or subcommand group rather than
precede it, and must precede a variadic `--` delimiter.
The technical publication sentinel and checklist now also name the two
remaining Kamal-specific gates explicitly: a retained end-to-end Linux AMD64
Proxy/Thruster deployment qualification and a retained recovery drill using
published Kamal-native backup/restore commands. The release cannot be declared
ready merely from the older internal Compose harness.
Final guard review made the release wrapper follow Kamal's current-directory
config semantics, normalized underscore config options, rejected image/hook
overrides hidden in short-option clusters, and intercepted Thor command
abbreviations plus one-level aliases that target setup or deployment. Dynamic
ERB and chained aliases fail closed because Kamal reparses those forms with
semantics the wrapper cannot safely infer. Git inspection now distinguishes a
valid checkout with no reachable release tag from an operational inspection
failure. Hosted deploy and redeploy hooks both check the candidate before
rolling work; every pre-app-boot checks again before migration, allowing only a
completely empty first-install database or a database where the stopped-process
credential migration is already applied.
