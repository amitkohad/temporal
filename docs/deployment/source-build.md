# Source release and build policy

All work stays on `codex/001-azure-temporal-deployment`. Application source is the approved fork `https://github.com/amitkohad/temporal`; the initial staging baseline is `717f485c760d1068aa310906466468e51120254f`. Its source metadata declares server 1.33.0, PostgreSQL persistence schema 1.19 and visibility schema 1.14. These values are rederived for each build and do not establish production readiness.

## Source and driver identity

`build-source.sh FULL_COMMIT EMPTY_OUTPUT_DIRECTORY` requires a full commit in the checked-out fork history, exports committed application source with `git archive`, and rejects a wrong origin or deployment branch. Controlled detached GitHub checkouts are accepted only for the configured repository/event/ref. Local uncommitted application changes are excluded. Both binaries and matching PostgreSQL schemas come from the same export. Go module checksums are verified and go.mod/go.sum must remain unchanged.

Deployment drivers may be developed separately from the chosen application baseline. Their repository HEAD, individual hashes, combined hash and dirty flag are recorded independently; hashes captured before compilation must match afterward. Local candidates can record dirty drivers, but published release validation rejects them. Commit/review the drivers on this same branch before publication. Do not create a release branch or merge to main.

## Toolchain and bases

Use Linux amd64, Go 1.27.2, `GOTOOLCHAIN=local`, `CGO_ENABLED=0`, and the repository's temporal-server/temporal-sql-tool Make targets with disable_grpc_modules. Deployment builds add `-trimpath -buildvcs=false`; external metadata records commit identity because a source archive has no Git directory. Go's module sum database remains enabled.

Verified standard Go parent: `golang:1.27.2-bookworm@sha256:5cf287a799e6b94384bad13d16b14904c531f51ba65792237e122ce42b392f61`. Local builders add Python through signed Debian packages and record their actual Docker image ID separately from the parent digest. Hosted CI uses pinned setup-go and records its exact toolchain version. The official Go Linux amd64 archive checksum is `ecbadb99091a3f46e31f5f934b068b1864eafa7995211b39eaddf76996045fe5`.

Runtime base: `gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab`. Both deployment Dockerfiles override the user to 1000:1000. The server runs temporal-server directly and accepts explicit CLI arguments; mount the later reviewed configuration under /etc/temporal/config. The SQL-tools image contains only the compiled SQL tool, matching schemas and standard runtime base. It has no Temporal CLI download, shell, compiler or automatic schema operation.

## Local candidate sequence

Run on a Linux amd64 host with git, Go, make, Python 3, Docker/buildx and standard shell utilities. Windows users can use their existing Linux Docker engine with reviewed read-only source mounts and a separate writable artifact directory. Compilation and scans require no Azure compute.

```bash
commit=717f485c760d1068aa310906466468e51120254f
base=gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
bash scripts/deployment/build-source.sh "$commit" .deployment-local/release/build
bash scripts/deployment/build-images.sh .deployment-local/release/build "$base" "nexusflow/temporal-server:$commit" "nexusflow/temporal-sql-tools:$commit"
bash scripts/deployment/install-release-tools.sh .deployment-local/release-tools
export PATH="$PWD/.deployment-local/release-tools:$PATH" TRIVY_VERSION=0.75.0
bash scripts/deployment/collect-release-evidence.sh .deployment-local/release/build .deployment-local/release/evidence
bash scripts/deployment/release-manifest.sh .deployment-local/release/build .deployment-local/release/evidence .deployment-local/release/candidate.json
bash scripts/deployment/validate-release.sh .deployment-local/release/candidate.json
```

Use empty output directories; evidence directories and manifests are created exclusively. Assembly rejects changed or additional binary/schema artifacts and changed driver files. Smoke checks should run --version/--help with `--read-only --cap-drop ALL --security-opt no-new-privileges --network none`. These checks establish executable packaging, not Temporal database/workflow readiness.

## Evidence and vulnerability policy

The installer pins Trivy 0.75.0 and checks the official Linux archive SHA-256 `c6e65abddb348e25f10549df887045629cf28cc72453cd1c63acb717316b3f3f` before extraction. Tool and OS dependencies are allowed; prebuilt Temporal runtime/admin images and externally downloaded Temporal application binaries are prohibited. The existing upstream admin-tools action downloads Temporal CLI and is not used by these deployment workflows.

Evidence includes binary and schema hashes, exact source/driver/toolchain identities, local image IDs, CycloneDX SBOMs, unsigned in-toto/SLSA-format provenance and raw vulnerability/secret/misconfiguration results. Generation verifies that packaged image bytes match the compiled artifacts. No SLSA assurance level or signature is claimed for local provenance.

Missing or substituted evidence, source/schema/image mismatch, secrets, unknown vulnerability severity, and unapproved HIGH/CRITICAL vulnerabilities block release. Exceptions require exact vulnerability/package/image identity, an accountable owner, reason and an unexpired date in evidence/exceptions.json. Do not invent an exception to make a scan pass. Fix the source/base dependency, rebuild and rescan; escalate a necessary exception for maintainer review. See [release evidence contract](../../scripts/deployment/RELEASE-EVIDENCE.md).

## Validation and later publication

azure-temporal-validate.yml builds PRs targeting the authoritative branch and pushes to that branch without Azure credentials, publication or mutation. It runs deployment policy tests and shell syntax checks, then compiles and assembles local images. Repository action pins are full immutable SHAs; the source checkout has no persisted GitHub credential.

azure-temporal-release.yml is manual-only. It requires a full reachable source commit and explicit readiness variables `AZURE_TEMPORAL_PUBLISH_ENABLED=true`, `AZURE_TEMPORAL_OIDC_SUBJECT_VERIFIED=true` and `AZURE_TEMPORAL_REGISTRY_WRITER_CLIENT_ID`. They are not configured by this phase. Set them only after verifying the protected staging environment, exact federated subject/audience and registry-scoped writer role. This identity must not have infrastructure/database/deployment write roles.

The credential-free candidate job builds/scans/validates first. A separate protected staging publication job verifies the transferred candidate and both loaded image IDs before OIDC login. It uses content-bound tags, refuses an existing tag for different bytes, verifies immutable registry references remotely, and writes a separate published manifest. Credentials are removed in an always-run step. It does not provision infrastructure, initialize schemas or deploy Temporal.

Local Docker image IDs identify image configuration, not OCI pull manifests. A candidate leaves registry_reference null and cannot pass --require-published. Promote the tested registry digests, never latest or a mutable tag. Preserve the complete build/evidence bundle so validation can recompute hashes.

References: [Go download catalogue](https://go.dev/dl/?mode=json), [distroless images](https://github.com/GoogleContainerTools/distroless), [Trivy 0.75.0](https://github.com/aquasecurity/trivy/releases/tag/v0.75.0). Actual phase results are in [Phase 4 implementation](../../specs/001-azure-temporal-deployment/phase-4-implementation.md).