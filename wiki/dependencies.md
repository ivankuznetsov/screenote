---
title: Dependencies
type: dependencies
source: Gemfile, Gemfile.lock
created: 2026-05-14
updated: 2026-11-04
tags: [dependencies]
---

**TLDR**: Dependency facts are derived from tracked dependency and plugin metadata files.

## Dependency Files

- `Gemfile`
- `Gemfile.lock`

## Notes

- Project type detected: Ruby on Rails application.
- Review dependency lockfiles directly before changing runtime assumptions.
- Rails is locked to 8.1.4.1 for the November 4, 2026 security release.
  Production must provide native libvips 8.13 or newer.
- The security refresh also locks rails-html-sanitizer 1.7.2, Loofah 2.25.3,
  and Nokogiri 1.19.7 through Rails' sanitizer dependencies.
- WEBrick is a test-only dependency for the isolated retry proxy and legacy
  server stub used by `script/public_cli_source_qualification`. Those stubs run
  through `bundle exec ruby`, so clean CI runners resolve the gem from the
  locked, isolated bundle rather than requiring a global installation.

- The November security audit also requires patched Rack 3.2.8, Addressable
  2.9.2, Crass 1.0.8, Net::SSH 7.3.8, and SQLite3 2.10.2.
