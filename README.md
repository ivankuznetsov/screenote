# Screenote

Screenote is a visual feedback workspace for screenshots. Teams can capture several viewports, place point or area comments directly on an image, reply and resolve in one review surface, and automate the same project-scoped workflow through OAuth, REST, the CLI, or MCP.

This repository is **source-available and self-hostable**. It contains both the unlimited self-hosted core and the explicitly enabled services Future Spin Ltd uses to operate `screenote.ai`.

> **Release status:** the first source release is being prepared. Do not treat an untagged branch, a moving image tag, or a candidate CLI build as a supported release. Publication remains blocked until the legal, full-history secret-review, GitGuardian, repository-protection, and exact-artifact gates in [the release guide](docs/releases.md) are complete.

## Self-host Screenote

The supported first-release topology is one Docker container, four SQLite databases on one durable volume, and either local or S3-compatible screenshot storage. It has no Stripe dependency, license key, or product limit.

Start with the [self-hosting guide](docs/self-hosting.md). It links the copyable Docker Compose install, secret setup, storage options, reverse-proxy configuration, health checks, backups, restores, upgrades, and rollback procedure. Always pin the immutable image digest named by a release; never operate from `latest`.

## CLI and automation

The canonical public CLI lives at [ivankuznetsov/screenote-cli](https://github.com/ivankuznetsov/screenote-cli). Each Screenote release names one exact tested CLI tag. Install that tag, not a moving branch:

```sh
go install github.com/ivankuznetsov/screenote-cli/cmd/screenote@<release-cli-tag>
screenote --base-url http://screenote.internal login
```

Use `login --device` from SSH, tmux, or another headless session. The Go client still present in this repository is transitional and is not a supported release artifact.

## Develop

Screenote is a Rails 8.1 application with a small transitional Go client. Run the normal quality gate before opening a pull request:

```sh
bin/setup --skip-server
bin/ci
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution expectations, [SECURITY.md](SECURITY.md) for private vulnerability reporting, and [SUPPORT.md](SUPPORT.md) for the support boundary.

## License

Copyright © 2026, Future Spin Ltd.

Screenote is distributed under the [O'Saasy License Agreement](LICENSE). It permits use, modification, and redistribution, but does not permit offering Screenote or a derivative to third parties as a directly competing hosted, managed, SaaS, or cloud service whose primary value is Screenote's functionality. The license text—not this summary—is authoritative.
