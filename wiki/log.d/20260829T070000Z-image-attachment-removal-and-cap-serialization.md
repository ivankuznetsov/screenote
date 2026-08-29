---
title: Image attachment removal and account-cap serialization
date: 2026-08-29
tags: [attachments, concurrency, cleanup]
---

Draft removal now reserves the browser's client key as a bounded tombstone,
so an aborted upload cannot create a ready row after the remove request looked
for it. Claim omits and destroys tombstones, while resume hides them.

Upload commit now takes the account lock before the batch lock when rechecking
the outstanding-draft byte ceiling. This serializes the cap across different
open composers. Variant reconciliation also selects a bounded SQL set of rows
that are actually missing a named thumbnail digest instead of scanning every
submitted attachment in Ruby.
