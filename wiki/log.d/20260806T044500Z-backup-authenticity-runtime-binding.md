# Backup authenticity and runtime binding

- Added an independent operator-held HMAC key so a public age recipient cannot be used to forge an apparently valid Screenote backup.
- Required the authentication key to be a dedicated restricted single-link file outside every archived input and distinct from configuration, Compose, the age identity, and running application storage.
- Bound backup to the running container's exact secret files and local Docker storage volume before quiescing.
- Authenticated restore input before Docker mutation, retained the isolated-container recheck, and passed the age identity through an inherited descriptor so interrupted restore cannot leave private-key staging residue.
- Tightened release authorization to one direct-parent evidence commit, exact final-byte scanning, a post-approval live incident gate, strict Trivy exit/schema checks, and redacted S3 hook streams.

Related: [[self-hosting]], [[testing-and-ci]], [[decisions]].
