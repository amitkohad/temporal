# Tasks: Source-built Temporal on Azure

**Branch**: codex/001-azure-temporal-deployment
**Input**: spec.md, plan.md, research.md, contracts/platform.md
**Status**: Phase 1 decisions in progress: T001, T002, T004, T005 and T006 complete; T003, T007 and T008 partial. Later phases pending. No cloud execution authorized.

Format: unchecked task ID, optional [P] for independently implementable work, [US#] story, action, path and completion evidence. Task completion requires the stated evidence. Phase owner roles are responsibilities, not assigned people. [P] does not authorize agent delegation.

Planning artifacts were generated directly following the GitHub Spec Kit workflow; no Spec Kit CLI or slash commands were installed/executed.

## Phase 1 — Inputs and release decisions

Owner: Platform owner / maintainer. Dependencies: None. Evidence and open inputs: [phase-1-decisions.md](phase-1-decisions.md).

- [x] T001 [US1] Resolve subscription, tenant, region, environment classification and rg-nexusflow existing/create ownership in specs/001-azure-temporal-deployment/research.md; evidence: accepted input register.
- [x] T002 [US1] Select naming, globally unique registry/storage names, CIDRs and environment/state isolation in docs/deployment/environment.md; evidence: collision and overlap review.
- [ ] T003 [US1] Verify regional AKS/PostgreSQL HA availability, VM/database quota, required Azure provider registrations and budget in docs/deployment/capacity.md; evidence: approved SKU/cost matrix.
- [x] T004 [US2] Select approved immutable source commit and validate available Go toolchain against go.mod in docs/deployment/source-build.md; evidence: release compatibility matrix.
- [x] T005 [US2] Confirm source-only boundary for base/toolchain images, managed services and platform agents in docs/deployment/source-build.md; evidence: explicit build policy.
- [x] T006 [US3] Record workload throughput/history/search demand, retention, latency and availability goals in docs/deployment/capacity.md; evidence: measurable acceptance targets.
- [ ] T007 [US4] Record RPO/RTO, backup retention, regional disaster-recovery decision and operational owners in docs/deployment/recovery.md; evidence: signed-off recovery profile.
- [ ] T008 [US1] Choose operator and CI private connectivity, DNS authority and federated identity bootstrap owner in docs/deployment/access.md; evidence: access topology and permissions.

## Phase 2 — Contracts and state bootstrap implementation

Owner: Infrastructure engineer. Dependencies: Phase 1 decisions.

- [ ] T009 [US1] Implement variable schemas, validations and stable output contracts in infra/terraform/environments/azure/{variables,outputs}.tf; evidence: invalid-input tests.
- [ ] T010 [US1] Define provider/version constraints and dependency lockfiles per root in infra/terraform/; evidence: approved provider matrix, repeatable initialization.
- [ ] T011 [US1] Implement rg-nexusflow existing/create modes with no ownership of unrelated resources in infra/terraform/environments/azure/main.tf; evidence: mocked ownership plans.
- [ ] T012 [US1] Implement state storage/container, encryption, versioning, soft delete, scoped access and locking prerequisites in infra/terraform/bootstrap/azure/; evidence: protected backend design and tests.
- [ ] T013 [US1] Document secure initial local state handling, remote-state migration, separate root keys and interrupted-bootstrap recovery in docs/deployment/bootstrap.md; evidence: rehearsable sequence without circular dependency.
- [ ] T014 [US1] Implement scoped OIDC federation and environment-bound trust configuration in infra/terraform/bootstrap/azure/; evidence: privilege matrix and untrusted-ref denial checks.
- [ ] T015 [US1] Add ignore rules for state, plan, local credentials and variable secrets in .gitignore; evidence: git-ignore verification.
- [ ] T016 [US1] Implement mocked Terraform contract tests for outputs and shared-resource protection in infra/terraform/tests/; evidence: offline passing tests.

## Phase 3 — Azure infrastructure implementation (US1)

Owner: Infrastructure engineer. Dependencies: Phase 2 contracts; no apply in this phase.

- [ ] T017 [US1] Implement VNet, isolated AKS/runner/PostgreSQL/endpoint subnets and validated routing in infra/terraform/modules/azure/network/; evidence: CIDR and route tests.
- [ ] T018 [US1] Implement delegated PostgreSQL subnet, private DNS links and required HA/storage egress in infra/terraform/modules/azure/network/; evidence: DNS/NSG configuration review.
- [ ] T019 [US1] Implement controlled AKS/runner egress and dependency allowlist in infra/terraform/modules/azure/network/; evidence: endpoints and ports documented.
- [ ] T020 [US1] Implement staging Basic ACR with authenticated public endpoint, disabled admin credentials and approved RBAC mode; preserve a private Premium option for production in infra/terraform/modules/azure/registry/; evidence: registry access tests.
- [ ] T021 [US1] Implement private AKS control plane, Entra integration and disabled local accounts where supported in infra/terraform/modules/azure/aks/; evidence: identity/DNS validation.
- [ ] T022 [US1] Implement a staging shared system pool and separate production system/user pools, supported zones, autoscale bounds and upgrade surge settings in infra/terraform/modules/azure/aks/; evidence: capacity and disruption review.
- [ ] T023 [US1] Implement OIDC/workload identity and kubelet registry reader assignments matched to registry mode in infra/terraform/modules/azure/aks/; evidence: scoped role matrix.
- [ ] T024 [US1] Implement PostgreSQL Flexible Server with accepted version/SKU, staging HA disabled and production HA configurable, backup/PITR and storage settings in infra/terraform/modules/azure/postgresql/; evidence: protected configuration tests.
- [ ] T025 [US1] Implement separate temporal/temporal_visibility databases and replacement/deletion safeguards in infra/terraform/modules/azure/postgresql/; evidence: nondestructive plans.
- [ ] T026 [US1] Implement private Key Vault, rotation/access controls and logical secret/certificate handoff in infra/terraform/modules/azure/security/; evidence: no secret-value outputs.
- [ ] T027 [US1] Implement minimal monitoring/log destinations, retention and diagnostics; no monetary spending cap by user instruction in infra/terraform/modules/azure/observability/; evidence: destination/owner matrix.
- [ ] T028 [US1] Implement independently bootstrappable ephemeral private runner infrastructure and short-lived registration in infra/terraform/modules/azure/runner/; evidence: no dependence on Temporal readiness, no persisted runner token.
- [ ] T029 [US1] Compose module dependencies and safe environment examples in infra/terraform/environments/azure/; evidence: validated complete configuration.
- [ ] T030 [US1] Implement protected-state and identity handoff to separate platform root in infra/terraform/platform/; evidence: no same-plan Kubernetes bootstrap and no admin kubeconfig export.
- [ ] T031 [US1] Write resource ownership/import/teardown documentation including AKS-managed node resource group in docs/deployment/infrastructure.md; evidence: shared rg-nexusflow cannot be destroyed accidentally.

## Phase 4 — Source build implementation (US2)

Owner: Build engineer / maintainer. Dependencies: Approved source policy; independent of cloud provisioning.

- [ ] T032 [US2] Implement pinned-commit checkout and source metadata verification in scripts/deployment/build-source.sh; evidence: reject mutable-only or wrong-origin revisions.
- [ ] T033 [US2] Reuse Makefile build flags/version metadata to compile Linux server and SQL tool in scripts/deployment/build-source.sh; evidence: source-built binary checksums and reported version.
- [ ] T034 [US2] Implement minimal SQL-tools Dockerfile with matching PostgreSQL schemas in docker/targets/sql-tools.Dockerfile; evidence: no external CLI/application binary downloads.
- [ ] T035 [US2] Adapt image assembly for fork provenance, UID 1000, architecture and approved base provenance in docker/targets/server.Dockerfile and deployment build configuration; evidence: runnable hardened images.
- [ ] T036 [US2] Implement build-only pipeline supporting codex branches and PRs in .github/workflows/azure-temporal-validate.yml; evidence: no publish or Azure mutation on PR events.
- [ ] T037 [US2] Generate SBOM, provenance, scan results and immutable release manifest in scripts/deployment/release-manifest.sh; evidence: schema/image/source consistency verification.
- [ ] T038 [US2] Implement future explicit image-publish stage with OIDC and scoped registry write identity in .github/workflows/azure-temporal-release.yml; evidence: environment-gated publication only.
- [ ] T039 [US2] Add build policy checks rejecting prebuilt Temporal images, CLI download path and latest deployment references in scripts/deployment/validate-release.sh; evidence: negative cases fail.
- [ ] T040 [US2] Document local source builds, promotion by digest and vulnerability exception policy in docs/deployment/source-build.md; evidence: maintainer review.

## Phase 5 — Safe database lifecycle implementation (US3)

Owner: Database engineer / maintainer. Dependencies: Release contract and database TLS/identity design.

- [ ] T041 [US3] Implement runtime versus migration-role bootstrap design and required SQL grants in deploy/temporal/schemas/roles.sql; evidence: DML succeeds and runtime DDL is denied.
- [ ] T042 [US3] Implement SQL connection TLS/CA/hostname verification and secret-reference mapping in deploy/temporal/schemas/; evidence: invalid CA or hostname rejected.
- [ ] T043 [US3] Implement initialize/upgrade/verify operation wrapper using repository SQL tools in scripts/deployment/schema.sh; evidence: empty, existing, newer and mismatched-schema paths.
- [ ] T044 [US3] Implement exclusive migration lease and bounded failure/retry behavior in scripts/deployment/schema.sh; evidence: concurrent migration denial and partial-failure handling.
- [ ] T045 [US3] Implement explicit schema Kubernetes Jobs with least-privilege credentials, deadlines and sanitized logs in deploy/temporal/schemas/jobs.yaml; evidence: no drop or automatic startup migration.
- [ ] T046 [US3] Test initialization rerun and upgrade against isolated PostgreSQL in deployment schema tests; evidence: workflow data preserved and both versions verified.
- [ ] T047 [US3] Document backup prerequisite, migration ordering, ownership, failure assessment and compatibility rollback in docs/deployment/schema.md; evidence: operator-reviewed runbook.

## Phase 6 — Portable Kubernetes and security implementation (US3)

Owner: Platform engineer / security owner. Dependencies: Contracts, source artifacts and safe schema lifecycle.

- [ ] T048 [US3] Pin compatible chart and verify fork image/config/entrypoint compatibility in deploy/temporal/values.yaml; evidence: documented version matrix and rendered role selection.
- [ ] T049 [US3] Configure separate frontend/history/matching/internal-worker services with pod address advertisement in deploy/temporal/values.yaml; evidence: correct ports and membership configuration.
- [ ] T050 [US3] Configure PostgreSQL pools for both stores and aggregate connection/surge budget in deploy/temporal/values.yaml; evidence: capacity calculation under peak replicas.
- [ ] T051 [US3] Record measured shard-count selection and prohibit changing it after initialization in deploy/temporal/values.yaml and docs/deployment/capacity.md; evidence: approved first-cluster settings.
- [ ] T052 [US3] Implement replicas, resources, topology spread, disruption budgets and safe scaling limits in deploy/temporal/values.yaml; evidence: sufficient spare capacity and sensible drain behavior.
- [ ] T053 [US3] Implement TLS-aware startup/readiness/liveness probes and graceful termination in deploy/temporal/values.yaml; evidence: restart does not create probe loops.
- [ ] T054 [US3] Implement client and internode TLS trust/certificate references and rotation procedure in deploy/temporal/; evidence: full handshake and rotation tests.
- [ ] T055 [US3] Implement approved claim-mapping/authorization configuration; if Go customization is required follow repository patterns in a scoped package; evidence: unauthorized requests denied and approved claims work.
- [ ] T056 [US3] Implement namespace RBAC, network policies, Pod Security and hardened pod settings in deploy/temporal/policies/; evidence: allowed service/membership/metrics/DNS/DB traffic and denied unrelated access.
- [ ] T057 [US3] Implement secret integration with Azure identity annotations isolated in deploy/temporal/azure.values.yaml; evidence: runtime pods cannot access migration credentials.
- [ ] T058 [US3] Implement private ClusterIP frontend for staging and an optional internal load balancer, with trusted client/private DNS handoff in deploy/temporal/azure.values.yaml; evidence: no public service endpoint.
- [ ] T059 [US3] Implement separate Helm/Kubernetes root referencing approved image digests and schema-readiness evidence in infra/terraform/platform/; evidence: infrastructure/schema gates before rollout.
- [ ] T060 [US3] Implement approved namespace registration and retention/limit configuration as an explicit later operation in scripts/deployment/namespaces.sh; evidence: no implicit registration during validation.
- [ ] T061 [US1] Implement portability checks preventing Azure resource IDs/annotations in shared values in scripts/deployment/validate-portability.sh; evidence: shared render works with neutral fixture endpoints.

## Phase 7 — Observability, operations and delivery controls

Owner: Operations / security / build engineers. Dependencies: Phases 3–6 implementations.

- [ ] T062 [US4] Implement service/persistence/task/host/database metrics dashboard definitions in deploy/temporal/monitoring/; evidence: all required signal categories mapped.
- [ ] T063 [US4] Implement actionable alert rules, log redaction, retention and ownership routing in deploy/temporal/monitoring/; evidence: alert fixtures and runbook links.
- [ ] T064 [US4] Write operator access, incident, credential/certificate rotation and drift runbooks in docs/deployment/operations.md; evidence: least-privilege access and escalation steps.
- [ ] T065 [US4] Write backup/PITR restore and regional recovery procedures in docs/deployment/recovery.md; evidence: isolated restore and shared-resource protection.
- [ ] T066 [US4] Write sequential server/schema/chart/Kubernetes/PostgreSQL upgrade and rollback constraints in docs/deployment/upgrades.md; evidence: compatibility and backup gates.
- [ ] T067 [US1] Implement static Terraform fmt/validate/mocked tests and Helm schema/policy validation in .github/workflows/azure-temporal-validate.yml; evidence: credential-free non-mutating checks.
- [ ] T068 [US1] Implement separate manual bootstrap/provision/publish/migrate/rollout stages with protected environments in .github/workflows/azure-temporal-release.yml; evidence: no automatic apply, trusted identity and review gates.
- [ ] T069 [US1] Implement state-lock contention, sanitized plan storage, concurrency and failed-stage resume controls in delivery workflows; evidence: safe concurrent-run/retry fixtures.
- [ ] T070 [US1] Document cost estimates, tags, free-benefit eligibility, attended stop/start and cleanup ownership; no spending cap in docs/deployment/costs.md; evidence: monthly cost assumptions and safe staging cleanup.
- [ ] T071 [US4] Implement source-built temporary smoke worker and representative load/failure harness under deployment test paths; evidence: no external prebuilt application-worker image.

## Phase 8 — Pre-execution review gate

Owner: Maintainer / platform owner. Dependencies: All applicable implementation/static checks.

- [ ] T072 [US1] Run and record static Terraform, contract, portability, workflow and Helm checks; evidence: specs/001-azure-temporal-deployment/checklists/implementation.md.
- [ ] T073 [US2] Run source build and provenance/security checks without publishing; evidence: candidate release manifest and validated image digests.
- [ ] T074 [US3] Read docs/development/testing.md and run relevant Go tests with test_dep, using integration only for integration tests, then make lint-code-fast after code changes; evidence: applicable command results.
- [ ] T075 [US1] Review resolved inputs, permissions, private runner bootstrap, infrastructure change plans, cost and recovery ownership; evidence: explicit go/no-go record.
- [ ] T076 [US1] Obtain separate user authorization before any cloud mutation, publication, schema operation or rollout; evidence: execution request identifying environment and release.

## Phase 9 — Future execution only: infrastructure and release

Owner: Authorized platform/database/build operators. Dependencies: Phase 8 authorization; NOT authorized by this request.

- [ ] T077 [US1] EXECUTION ONLY: bootstrap state and OIDC prerequisites, protect/migrate initial state and verify locking using docs/deployment/bootstrap.md; evidence: protected backend and clean migration.
- [ ] T078 [US1] EXECUTION ONLY: review and apply infrastructure plans for network, private registry, identities, runner, AKS, PostgreSQL and monitoring; evidence: outputs/ownership/plan audit without unexpected replacements.
- [ ] T079 [US1] EXECUTION ONLY: verify private runner/operator routes, DNS, registry access and state/Key Vault access; evidence: allowed and denied connection tests.
- [ ] T080 [US2] EXECUTION ONLY: build/scan/sign or attest and publish approved source images to new ACR; evidence: release manifest and independently verified digests.
- [ ] T081 [US3] EXECUTION ONLY: establish PostgreSQL roles, runtime/migration secrets and TLS material; evidence: least privilege and verified encrypted connections.
- [ ] T082 [US3] EXECUTION ONLY: back up as applicable, acquire migration lease, run matching schema Jobs and verify both versions; evidence: nondestructive schema audit.
- [ ] T083 [US3] EXECUTION ONLY: roll out four Temporal services, verify health and register approved namespaces; evidence: digest/config/schema match and private frontend access.

## Phase 10 — Future execution only: readiness and handover

Owner: Operations / application / database / security owners. Dependencies: Successful Phase 9; isolated staging permission.

- [ ] T084 [US3] EXECUTION ONLY: run source-built smoke workflow and visibility/search checks across restarts; evidence: stable history and completion.
- [ ] T085 [US3] EXECUTION ONLY: test denied client/network access, TLS verification, runtime DDL denial and certificate/credential rotation; evidence: security readiness report.
- [ ] T086 [US4] EXECUTION ONLY: load-test representative history/search mixes and tune capacity/pools while freezing shard decision before production; evidence: throughput/latency/headroom results.
- [ ] T087 [US4] EXECUTION ONLY: rehearse pod/node drain, node loss and PostgreSQL failover under load; evidence: recovery behavior and accepted availability results.
- [ ] T088 [US4] EXECUTION ONLY: validate alert delivery and incident runbook with controlled faults; evidence: owner acknowledgement and detection time.
- [ ] T089 [US4] EXECUTION ONLY: restore PITR/backup into isolated resources and verify workflows/visibility against RPO/RTO; evidence: timed restore report.
- [ ] T090 [US4] EXECUTION ONLY: rehearse supported sequential schema/server upgrade and constrained rollback; evidence: workflow continuity and compatibility results.
- [ ] T091 [US4] EXECUTION ONLY: record production acceptance, residual risks, on-call ownership and approved promotion; evidence: operational readiness sign-off.
- [ ] T092 [US1] EXECUTION ONLY: clean up only explicitly owned disposable staging resources, retaining shared group/state/backups as required; evidence: reviewed cleanup plan.

## Dependencies and delivery order

Phase 1 decisions precede concrete version/capacity choices. Phase 2 contracts and state design unblock Azure modules. Source build work can proceed independently of resource provisioning after source policy is accepted. Schema and Kubernetes work require shared contracts; observability and CI consume their final interfaces. All implementation tasks pass Phase 8 before any Phase 9 execution. Phase 10 requires isolated staging and a working release.

Within a phase, contract/identity/network outputs precede consumers. Parallel implementation is possible for separate Azure modules after network/identity contracts settle, source build versus infrastructure, and dashboards versus runbook drafting. Do not parallelize migrations, shared state operations or deployment mutations.

MVP staging sequence: US1 foundation -> US2 source artifacts -> US3 safe schema and private service -> US4 readiness. US4 recovery/security validation is still required before production acceptance.

## Requirement traceability

| Requirements | Tasks |
|---|---|
| FR-001 | T020–T025, T078 |
| FR-002 | T001, T011, T031 |
| FR-003 | T011, T016, T031, T092 |
| FR-004 | T002, T008, T017–T019, T021, T028, T079 |
| FR-005 | T012–T016, T069, T077 |
| FR-006 | T009, T030, T061, T072 |
| FR-007 | T004, T032–T035, T073 |
| FR-008 | T005, T034, T039 |
| FR-009 | T037, T039, T073, T080 |
| FR-010 | T014, T036, T038, T068 |
| FR-011 | T008, T014, T023, T028, T068, T079 |
| FR-012 | T024–T025, T043, T048, T050, T082 |
| FR-013 | T043–T046, T082 |
| FR-014 | T026, T041–T042, T045, T057, T081, T085 |
| FR-015 | T049, T059, T083 |
| FR-016 | T056, T058, T079, T085 |
| FR-017 | T054–T055, T064, T085 |
| FR-018 | T022, T052–T053, T087 |
| FR-019 | T006, T050–T051, T060, T086 |
| FR-020 | T027, T062–T064, T088 |
| FR-021 | T007, T024, T065, T089 |
| FR-022 | T047–T048, T066, T090 |
| FR-023 | T046, T071–T074, T084–T090 |
| FR-024 | T036, T067–T069, T072 |
| FR-025 | T068, T075–T076; T077–T092 gated |
| FR-026 | T001–T008, T029–T031, T040, T047, T064–T070, T075 |

Traceability is reviewed against final generated task numbering during document verification. Future task edits must update this table.

## Definition of done
Planning: feature catalogue, prioritized specification, decisions, technical plan, contracts, data model, review checklist and uniquely numbered task backlog exist with all requirements covered.
Implementation: all applicable tasks through the review gate have real evidence; no unresolved deployment inputs.
Deployment: separately authorized execution and readiness evidence; documentation or Terraform validation alone is not a deployed service.
