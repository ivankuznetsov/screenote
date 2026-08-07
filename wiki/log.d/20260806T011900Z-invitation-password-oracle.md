## [2026-08-06] Keep existing-account passwords out of invitation acceptance

**Action:** Removed password verification for existing users from the reusable invitation endpoint. Existing invitees now authenticate through the ordinary rate-limited session flow and accept only through a matching signed-in identity; inline password creation remains available only when the invited address has no account. Added repeated-guess, multiple-link, controller, and real-browser admission regressions.

**Pages updated:** wiki/decisions.md, wiki/log.d/20260806T011900Z-invitation-password-oracle.md, wiki/log.md

**Source:** `app/services/project_invitations/accept.rb`, invitation acceptance UI/controller regressions, and self-hosted admission system coverage
