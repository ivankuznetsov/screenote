---
title: InstallationAuditEvent
type: model
source: app/models/installation_audit_event.rb
created: 2026-08-05
updated: 2026-08-05
tags: [model, installation, audit]
---

# InstallationAuditEvent

TLDR: Append-only primary-database history for installation claim and later account-administration transitions.

Each event belongs to the installation and records a normalized machine event type, structured JSON metadata, creation time, and optional actor/target users. Persisted rows are readonly, and restrictive foreign keys keep referenced installation/user identities from erasing the audit trail.

See also: [[data-model]], [[schema-evolution]], [[self-hosting]], [[models/user]]
