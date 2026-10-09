# Guarded schema executor packaging

`docker/targets/schema-runner.Dockerfile` packages the fork-built SQL tool, renewable Entra token helper and guarded schema wrapper with Debian's Bash, Python, PostgreSQL client and CA tooling. Its official Debian bookworm-slim base index digest was verified through the Docker registry on 2026-10-09. Apt packages are resolved during the build; their actual versions and final image content must be recorded by SBOM/provenance and vulnerability scans. Base pinning alone does not establish bit-for-bit package reproducibility.

This is a new executor artifact, not the frozen Phase 4 distroless SQL-tools image. Use a dedicated context containing only:

```text
release/
  release.json
  build/                          # Complete validated binary/schema metadata and artifacts.
  evidence/                       # Complete scan, SBOM and provenance files.
  executor/entra-token            # Freshly compiled from the same full fork source commit.
scripts/deployment/
  schema.sh
  schema-operation.py
  release-evidence.py
```

Compile the helper from the pinned fork source with `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -buildvcs=false -o executor/entra-token ./cmd/tools/entra-token`. It is not downloaded as an application binary. Qualify its source commit and SHA-256 in the published bundle's `auxiliary_binaries.entra-token` record, including the bundle-relative path `executor/entra-token`. Do not fabricate that qualification or add an untracked helper to the frozen build metadata. The helper reads the current projected workload assertion on every invocation and exchanges it only for an expiring PostgreSQL token.

Before any production schema Job, extend the release contract/publisher to qualify this executor's immutable image digest, source/helper/wrapper checksums, infrastructure package SBOM and scan results. Rebuild all application artifacts from a commit containing the helper. Both the core bundle and helper must satisfy the wrapper's published-source checks. The present Jobs remain suspended with an unresolved executor image until those gates are met; this packaging file alone does not constitute a deployable release.

The Job supplies a database-specific workload-identity service account, explicit projected token with audience `api://AzureADTokenExchange`, tenant/client references and PostgreSQL Entra principal name. No static PostgreSQL password, client secret, default service-account API token or DB administration identity is embedded in the image or manifest. Separate migration identities are federated to their own namespace/service-account subjects and granted membership only in their database's migration role. Job RBAC, identity federation and private DNS/CA are subsequent execution prerequisites.

Mounted CA and assertion files are read-only. The wrapper forces verified PostgreSQL TLS, obtains fresh tokens before bounded SQL sessions, retains an exclusive migration guard and stops on partial failure. Root filesystem is read-only at Job execution; only a bounded in-memory `/tmp` volume is writable. Job defaults never deploy, resume or run migrations during server startup.

Build from the isolated context, never the workspace root: the root `.dockerignore` predates deployment state files and does not exclude every local state/credential artifact. Do not send `.deployment-local`, Terraform states, local inputs or Azure/GitHub credentials to the Docker daemon. No production executor build, publication, identity grant or Job application is claimed by this directory.