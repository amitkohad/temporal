# Source release and build policy

Date: 2026-10-09. All implementation stays on codex/001-azure-temporal-deployment.

## Selected source baseline
Repository: https://github.com/amitkohad/temporal
Selected immutable staging baseline: 717f485c760d1068aa310906466468e51120254f, the branch HEAD inspected when Phase 1 started.
Its parent inspection baseline was 4b74f358be4f58bc1d1841548b25d23a1210761e.
Server metadata: common/headers/version_checker.go declares 1.33.0.
PostgreSQL schema metadata: persistence 1.19 and visibility 1.14.
No release tag points at the selected HEAD. Version metadata does not prove upstream release qualification or production readiness.

Future implementation commits will remain on this branch. Each actual candidate build must pin its own full commit, include the implementation files, rederive version/schema checksums and pass build/release validation. The Phase 1 baseline is not an instruction to deploy an earlier commit that lacks future deployment code. Do not create release branches or merge to main.

## Toolchain compatibility
go.mod requires Go 1.27.0. Select Go 1.27.2, stable and available in the official download catalogue on 2026-10-09.
Linux amd64 archive: go1.27.2.linux-amd64.tar.gz.
SHA-256: ecbadb99091a3f46e31f5f934b068b1864eafa7995211b39eaddf76996045fe5.
Validate the official archive digest when installing; pin container digest separately if using a toolchain container.
Go is not installed on the local PATH. Terraform 1.10.5 windows_386 and Docker client 29.6.2 were observed. Docker engine readiness, toolchain execution, source compilation and Terraform/provider compatibility were not tested. Phase 1 selects available tooling; installation and actual builds belong to subsequent build tasks.

## Source-only boundary
The user selected standard Go/toolchain and OS base images plus Azure-managed services/platform agents while requiring Temporal application binaries to be built from this repository.
- Compile temporal-server and temporal-sql-tool from the same source commit using repository build flags.
- Package matching SQL schemas; produce separate server and minimal SQL-tools images.
- Do not use published temporalio/server or admin-tools images.
- Do not download Temporal CLI or any other application binary.
- The existing admin-tools pipeline downloads CLI; do not reuse that path unchanged.
- Base OS/toolchain provenance, digest pins, licenses, SBOM and scans remain required.
- Azure control plane, managed PostgreSQL and required platform agents are infrastructure dependencies; this repository is not their source.
- Application workers and Web UI are excluded from initial scope. Build a small test worker from checked-in code when validating workflows.

## Release acceptance
Before publishing, prove compile/run compatibility, reported metadata, image hardening, matching schema versions, immutable digests and scan policy. Never label the baseline as a validated production release. Promote the same tested digests; do not deploy latest.

Toolchain evidence: [official Go download catalogue](https://go.dev/dl/?mode=json). Repository build evidence: Makefile, docker/targets/server.Dockerfile, docker/targets/admin-tools.Dockerfile, .github/actions/build-docker-images/action.yml and schema/postgresql/v12/version.go.
