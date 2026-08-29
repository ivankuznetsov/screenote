---
title: Image attachment composer recovery
date: 2026-08-29
tags: [attachments, browser, recovery, accessibility]
---

The shared attachment composer now keeps its hidden batch identity across a
Stimulus disconnect, reloads the authoritative rows through the batch resume
endpoint, and rebuilds previews/listeners once. Interrupted uploads are polled
through a bounded settling window while submission remains disabled.

Draft removal is addressed by client key and remains visible when the DELETE
cannot be confirmed, so a network failure cannot hide a row that claim could
still attach. Alt-text PATCHes are serialized per image and submission waits
for the final typed value. Permanent validation errors no longer offer Retry;
transport and server upload failures still do.
