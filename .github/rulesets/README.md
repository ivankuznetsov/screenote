# Ruleset templates

These JSON files are reviewed fail-closed templates. They are not evidence that a GitHub setting exists, and `release-tags.json` is intentionally not directly applicable while its release-integration `actor_id` is `0`.

Before source publication:

1. Inspect the actual check runs for a protected candidate commit.
2. Replace each `integration_id: 0` with the installed GitGuardian GitHub App ID. Do not accept a same-named check from another integration.
3. Replace the tag ruleset's `actor_id: 0` with the narrow GitHub App installation that performs release promotion. Do not use a user, repository-role, administrator, team, or deploy-key bypass.
4. Confirm the required product contexts are exactly `CI / ruby-security`, `CI / lint`, `CI / coverage`, `CI / sqlite`, `CI / postgresql`, `CI / system-collaboration`, `CI / public-cli`, `CI / container-local`, `CI / container-s3`, `CI / backup-restore`, and `CI / release-artifact`. Every check must apply to pull requests and the protected default-branch SHA. Verify the metadata-only incident workflow's explicit status is attached to the exact PR head or test-merge SHA GitHub requires, not only the `pull_request_target` base SHA.
5. Apply all three rulesets with no additional bypass actor. Export each installed ruleset through GitHub's API, independently inspect it, canonicalize the JSON, and record its SHA-256 in restricted and public release evidence.
6. Confirm Ruleset Insights show direct pushes, force-pushes, deletions, and tag replacement blocked.

The main template has no bypass actor. The tag-creation template allows only the release integration to create a new `v*` ref. A separate tag-immutability ruleset has no bypass, so update, force-push, and deletion remain prohibited even for that integration. The workflow must still compare any existing object and stop on mismatch.

Official GitHub ruleset documentation: <https://docs.github.com/en/rest/repos/rules>.
