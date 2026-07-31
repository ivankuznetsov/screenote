---
title: Dependencies
type: dependencies
source: Gemfile, Gemfile.lock
created: 2026-05-14
updated: 2026-07-31
tags: [dependencies]
---

**TLDR**: Dependency facts are derived from tracked dependency and plugin metadata files.

## Dependency Files

- `Gemfile`
- `Gemfile.lock`

## Notes

- Project type detected: Ruby on Rails application.
- Review dependency lockfiles directly before changing runtime assumptions.
- Rails is locked to 8.1.3.1 for the CVE-2026-66066 Active Storage/libvips
  security fix. Production must provide native libvips 8.13 or newer.
- The same security refresh locks Loofah 2.25.2 and
  rails-html-sanitizer 1.7.1 so the repository's gem-audit gate is clean.
