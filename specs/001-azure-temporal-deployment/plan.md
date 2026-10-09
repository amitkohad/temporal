# Implementation Plan: Source-built Temporal on Azure

**Branch**: codex/001-azure-temporal-deployment | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)
**Status**: Phase 1 decision work started; later implementation and all deployment pending. See [phase-1-decisions.md](phase-1-decisions.md).

## Summary
Prepare a source-built Temporal service using new AKS and ACR resources and managed PostgreSQL in rg-nexusflow. Define Terraform Azure infrastructure adapters and a reusable Kubernetes layer. Execute no provisioning, publishing, migration or rollout during this planning request.

## Technical Context
Language: Terraform HCL, Helm YAML, shell/PowerShell automation; Go for source compilation and meaningful test utilities.
Source: inspected commit 4b74f358be4f58bc1d1841548b25d23a1210761e; select approved release before execution.
Toolchain: Go version from selected go.mod (currently 1.27.0), version-pinned Terraform/providers/Helm/chart/Kubernetes/PostgreSQL after compatibility research.
Storage: PostgreSQL persistence and visibility; Azure Blob remote Terraform state; Key Vault secret/certificate references.
Target: private AKS, Linux amd64 initially; staging uses one shared pool and a non-HA database, while production requires separate pools and accepted availability settings.
Performance: throughput, history size, latency, connection budget and search load are unresolved sizing inputs.
Testing: static HCL/render/workflow checks first; source builds and future isolated staging integration/failure/recovery checks later.
Scope: Temporal server and SQL tools; excludes production application workers, UI, second-cloud adapter and automatic regional replication.

## Constitution Check
- Source-only Temporal artifacts: satisfied by planned SQL-tools replacement; existing CLI download path prohibited.
- Portability: satisfied through contracts and adapters, not a universal cloud-resource module.
- Safe state: explicit schema release stage and restore gates; no destructive Makefile schema target.
- Security: private data paths and scoped identity contracts; authentication/authorization require implementation proof.
- Verification: every requirement maps to tasks; sizing claims await measurement.
- Execution boundary: only branch and Markdown artifacts created now.
Approved staging exception: Basic ACR uses an authenticated public endpoint to minimize cost. Temporal/PostgreSQL remain private. Single-node/no-HA settings apply only to staging. No spending cap is requested.

## Project Structure (planned implementation)
- infra/terraform/bootstrap/azure/: state storage, federation/bootstrap prerequisites; its own protected initial state.
- infra/terraform/modules/azure/{network,registry,aks,postgresql,security,observability,runner}/: concrete Azure resources.
- infra/terraform/environments/azure/: composition and safe example variables; no stored credentials.
- infra/terraform/platform/: reusable helm/kubernetes delivery root, separate state and provider initialization.
- deploy/temporal/{values.yaml,azure.values.yaml,schemas/,policies/}: portable values plus isolated Azure overrides.
- docker/targets/sql-tools.Dockerfile: minimal source-built schema tool.
- scripts/deployment/: input validation, build, release-manifest, and operation wrappers with explicit modes.
- .github/workflows/azure-temporal-validate.yml: PR-safe checks only.
- .github/workflows/azure-temporal-release.yml: future manually gated build/publish/provision/migrate/rollout stages.
- docs/deployment/: setup, source build, operations, recovery, upgrade and cost guidance.
No executable files in these paths are introduced by this planning change.

## Architecture and ownership
Terraform bootstrap owns state storage/identity prerequisites. Azure infrastructure owns VNet/subnets/DNS/egress, ACR, AKS, PostgreSQL, Key Vault, monitoring and private runner infrastructure. Platform root owns namespace/policies/secrets integration and Helm release; schema operation is an explicit prerequisite, not a hidden Helm hook.
AKS uses its managed node resource group for managed resources; parent remains rg-nexusflow. Existing resource-group mode references the group and never manages unrelated resources.
Two PostgreSQL databases may initially share an HA server; separate sizing and roles remain explicit. Aggregate connection limits account for every datastore pool across all service replicas and rollout surge.
Server/frontend/auth and internal service membership/TLS remain Temporal responsibilities; network privacy does not replace authorization.

## Delivery sequence (future authorized work)
1. Resolve input register, ownership, compatibility, cost and source-only boundary.
2. Implement and statically validate contracts, bootstrap and Azure modules.
3. Implement build-only source compilation/image pipeline, SQL safety logic and portable Kubernetes configuration.
4. Obtain explicit authorization for cloud execution with reviewed plans.
5. Bootstrap state/federation, migrate protected state, provision networking/registry/runner and infrastructure.
6. Build, scan, publish approved source images and capture release manifest.
7. Establish runtime identities, database roles, TLS/secrets and run serialized schema Jobs.
8. Roll out four Temporal services using immutable digests, then register approved namespaces.
9. Prove security, workflow/visibility behavior, failure recovery, capacity, backup restore and upgrade behavior.
10. Obtain operational acceptance and hand over runbooks.
Do not merge all provider bootstrap phases into a single Terraform apply.

## Validation strategy
Planning change: verify document links, unique task IDs, requirement coverage, complete placeholders, branch isolation and git diff whitespace.
Implementation: terraform fmt -check, init -backend=false for static provider setup only, validate and mocked terraform test; no credentials or mutation in PR checks. Validate lock files and approved provider versions. Render Helm and validate schema/policies/probes/TLS paths/image provenance.
Build: inspect no downloaded Temporal binaries; use repository build flags; meaningful Go changes require repository testing guide, test_dep tests and make lint-code-fast.
Staging-only: use test_dep,integration for repository integration tests; execute approved smoke/load/failure drills against isolated environments. Classify cleanup by ownership and preserve durable/shared resources.

## Risks and mitigations
- Private runner bootstrap deadlock: management-plane provisioning before runner-dependent application stages.
- Resource group ownership ambiguity: explicit create/reference mode, import runbook, deletion protection.
- Toolchain or chart incompatibility: preflight matrix and version pins; no guessed release equivalence.
- Destructive initialization: new schema tooling excludes drop operations and checks current versions.
- Azure outages/capacity: assess zone support/quota and explicitly choose regional DR policy.
- Secret exposure: scoped state access and artifact retention, no plaintext examples or logging.
- Future provider portability costs: only Azure adapter implemented initially; contract tests enforce the boundary.

## Phase 1 selected profile

Use existing rg-nexusflow in Central India, staging, AKS Free with one D2s_v5 node, Basic ACR, PostgreSQL B1ms without HA, private frontend/database and an ephemeral private runner. Approved toolchain/base images are allowed; Temporal binaries remain source-built. See the five docs/deployment decision documents for costs, names, CIDRs, source pin and open ownership/quota gates. Never create another branch or merge into main.
