# Contributing to Screenote

Thanks for helping improve Screenote. This repository is source-available under the [O'Saasy License Agreement](LICENSE), not an OSI-approved open-source license. By submitting a contribution, you represent that you have the right to submit it and agree that it may be distributed under the repository's license. This is not a contributor license agreement.

## Before you start

- Search existing issues and pull requests before starting substantial work.
- Open an issue first for a large product or architecture change so maintainers and contributors do not duplicate effort.
- Never put a suspected vulnerability, credential, private deployment detail, customer data, or private screenshot in a public issue. Follow [SECURITY.md](SECURITY.md) instead.
- Keep changes focused. Do not bundle unrelated formatting, generated files, or refactors into the same pull request.

## Development setup

Screenote requires the Ruby and system dependencies described by the Dockerfile. Prepare the development databases and run the application with:

```sh
bin/setup
bin/dev
```

Before submitting, run:

```sh
bin/ci
script/release_test_matrix self-hosted
```

Changes to authentication, authorization, persistence, deployment, or release behavior also need focused regression tests on each affected database adapter and edition. Browser-facing changes need system coverage for keyboard use, narrow screens, and the affected multi-user flow.

## Pull requests

A useful pull request:

- explains the user-visible outcome and the reason for the change;
- includes tests that fail without the change;
- calls out data, configuration, self-hosted, SaaS, API, security, and upgrade effects;
- updates operator documentation and the project wiki when behavior or architecture changes;
- contains no generated credentials, local environment files, production configuration, or sensitive scanner output; and
- passes every required status check, including GitGuardian. A pending, unavailable, skipped, or failed security check is not a pass.

Maintainers may ask for a smaller change, a different implementation, or additional evidence. A contribution is not accepted until it is reviewed and merged.

## Dependency and generated-file changes

Pin dependency and GitHub Action updates to immutable versions or full commit SHAs. Update `THIRD_PARTY_NOTICES.md` when a bundled dependency or its license changes. Do not hand-edit generated schema or compiled asset output independently of the source change that produces it.

## Release authority

Contributing code does not authorize a release. Repository visibility, tags, images, security-incident response, and the protected release environment remain maintainer-controlled operations described in [docs/releases.md](docs/releases.md).
