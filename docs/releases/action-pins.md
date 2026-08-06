# Release dependency pins

Every external Action in the repository is locked to a full 40-character commit. The comments in workflow files are review labels only; automation executes the commit, never the moving tag or branch. Updating a pin requires reviewing the exact upstream diff, updating this inventory, and rerunning the workflow and artifact contracts.

The production Dockerfile likewise uses the immutable multi-architecture index `docker.io/library/ruby:3.4.10-alpine3.24@sha256:c5a5064d190055633011c03aa800170cc36945ff3afb5f6c915329f92d6f1e00`. Release evidence must independently resolve that index and record the exact platform manifests used for the candidate.

These refs were resolved from their official GitHub repositories on 2026-08-06:

| Action reference used | Reviewed upstream ref | Purpose |
| --- | --- | --- |
| `actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803` | `actions/checkout` `v6` | Exact source checkout |
| `ruby/setup-ruby@95ef2b042f9d7a56d8268cba8559e2842e2ad01b` | `ruby/setup-ruby` `v1` branch snapshot, observed 2026-07-22 | Ruby and Bundler setup |
| `actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830` | `actions/cache` `v4` | RuboCop cache |
| `actions/setup-go@924ae3a1cded613372ab5595356fb5720e22ba16` | `actions/setup-go` `v6` | Transitional Go contract |
| `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02` | `actions/upload-artifact` `v4` | Retained candidate, exact qualification/check records, and failed-test output |
| `actions/download-artifact@634f93cb2916e3fdff6788551b99b062d0335ce0` | `actions/download-artifact` `v5` | Exact-run candidate and live artifact-ID qualification retrieval |
| `docker/setup-qemu-action@c7c53464625b32c7a7e944ae62b3e17d2b600130` | `docker/setup-qemu-action` `v3.7.0` | ARM64 emulation |
| `docker/setup-buildx-action@8d2750c68a42422c14e847fe6c8ac0403b4cbd6f` | `docker/setup-buildx-action` `v3.12.0` | One-time multi-platform OCI build |
| `actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1` | `actions/create-github-app-token` `v3.2.0` | Narrow release-integration token |
| `actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6` | `actions/attest` `v4.2.2` | Manifest provenance attestation |

GitHub recommends full-length commit pins as the only immutable way to consume an Action: <https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions>.

## Checksum-pinned release tools

The release workflow downloads fixed release archives and verifies their lowercase SHA-256 before extraction:

| Tool | Official release archive | SHA-256 |
| --- | --- | --- |
| ggshield 1.52.2 | `GitGuardian/ggshield` `ggshield-1.52.2-x86_64-unknown-linux-gnu.tar.gz` | `181b440917943e1efac0ff58403b24181fddc152f0f2be7a932911a588eba03c` |
| Trivy 0.70.0 | `aquasecurity/trivy` `trivy_0.70.0_Linux-64bit.tar.gz` | `8b4376d5d6befe5c24d503f10ff136d9e0c49f9127a4279fd110b727929a5aa9` |
| Syft 1.44.0 | `anchore/syft` `syft_1.44.0_linux_amd64.tar.gz` | `0e91737aee2b5baf1d255b959630194a302335d848ff97bb07921eb6205b5f5a` |
| ORAS 1.3.2 | `oras-project/oras` `oras_1.3.2_linux_amd64.tar.gz` | `9229ccc6d17bb282039ad4a69abb16dcb887a5bce567c075d731d9b3c7ad8eaf` |

The Syft, Trivy, and ORAS values come from their official release checksum manifests. The ggshield value is the digest GitHub reports for the immutable release asset. Trivy 0.70.0 was selected only after reviewing Aqua's official [2026 supply-chain advisory](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23); the compromised versions named there are not used.

`skopeo` is installed from the runner's signed Ubuntu package repository solely to import retained OCI content into the local Docker scanner target. Its exact version is recorded in `candidate.json`, and the workflow compares the imported manifest and configuration digests to the retained OCI descriptors before either scanner can pass. It is not the vulnerability scanner and cannot authorize publication by itself.
