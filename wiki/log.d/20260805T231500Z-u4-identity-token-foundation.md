---
title: Admission identity and authentication-token foundation
date: 2026-08-05T23:15:00Z
---

- Added fail-before-mutation identity preflights and canonical database constraints without losing SQLite user child graphs.
- Added active/suspended user state and durable pending/accepted/cancelled invitations.
- Added append-only installation audit events and digest-only, exact-purpose authentication-token rows with NULL-safe partial uniqueness on SQLite and PostgreSQL 16.
