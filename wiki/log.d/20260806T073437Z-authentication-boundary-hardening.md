---
date: 2026-08-06T07:34:37Z
scope: authentication-security
---

Closed four browser authentication boundaries found during the source-release
review. Password login now uses Active Record's timing-safe `authenticate_by`
before active/suspended policy; one-time recovery and invitation presentations
are removed before Turbo snapshot caching and delivered with private no-store
headers; transient authentication-link database failures return retryable 503
responses while the scrubbed raw credential remains only in Stimulus memory;
and invitation OAuth callbacks require an exact local request-intent marker so
stale invitation context cannot capture ordinary provider sign-in. OmniAuth's
POST validator is also bound to Rails' real `:_csrf_token` session key, with a
positive Rails-form request-phase regression alongside missing/invalid-token
rejection.
