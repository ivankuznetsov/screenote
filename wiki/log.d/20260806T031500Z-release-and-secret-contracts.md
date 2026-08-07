# Release and recovery boundary preflights

- Made every publication rerun the no-checkout GitGuardian incident gate after retained-evidence authorization.
- Classified image, source tag, provenance attestation, and GitHub release together before the first mutation; only strict exact prefixes can resume.
- Signed the retained candidate provenance as a custom predicate, binding its certificate to the authorizing workflow SHA and its decoded statement to the built source identity.
- Bound backup and restore to the exact file-backed Compose secrets consumed by `screenote`, portable configuration-relative paths, and a sanitized Docker environment.

See [[self-hosting]], [[testing-and-ci]], and [[architecture]].
