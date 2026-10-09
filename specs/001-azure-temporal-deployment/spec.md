# Feature Specification: Source-built Temporal on Azure

**Feature Branch**: codex/001-azure-temporal-deployment
**Created**: 2026-10-09
**Status**: Draft — implementation not started
**Input**: Managed Kubernetes on Azure, PostgreSQL, no existing AKS or ACR, resource group rg-nexusflow, Terraform with portable boundaries, Temporal artifacts built from the provided repository; generate planning artifacts and do not deploy.

## User Scenarios & Testing

### US1 — Prepare repeatable infrastructure (Priority: P1)
As a platform operator, I want reviewed infrastructure definitions and a non-deploying validation process so a new environment can later be provisioned reproducibly.

Independent test: validate isolated Terraform roots and mocked contracts without Azure credentials; inspect plans only in a subsequently authorized environment.

Acceptance:
1. Given no AKS or ACR, when definitions are implemented, they describe creation of both plus networking, PostgreSQL, identities, secret storage, monitoring, and state bootstrap.
2. Given rg-nexusflow may already exist, when resource-group mode is selected, the configuration references it or explicitly creates it without claiming ownership of unrelated resources.
3. Given an environment change, validation checks inputs and returns errors without applying resources.
4. Given another cloud, shared Temporal values and contracts can be reused with a future adapter; no Azure IDs leak into shared configuration.

### US2 — Produce trustworthy source-built images (Priority: P1)
As a maintainer, I want source-built server and SQL-tool images so every release is attributable to our approved source.

Independent test: local/CI build evidence includes commit, toolchain, schema versions, SBOM, checksums, and image digests; no published Temporal image or downloaded application binary supplies runtime code.

Acceptance:
1. An immutable source commit determines both images and included SQL schemas.
2. The SQL-tool image excludes the existing downloaded CLI dependency.
3. The same tested digests are promoted between environments; no deployment uses latest.
4. An unapproved source ref, missing toolchain, or security-policy failure stops release preparation.

### US3 — Run durable workflows privately (Priority: P1)
As an application owner, I want a privately reachable Temporal service with PostgreSQL persistence so workflows survive infrastructure disruptions.

Independent test: future staging workflow with a temporary source-built test worker completes, remains discoverable, and resumes after service restart and database failover.

Acceptance:
1. Both temporal and temporal_visibility are initialized from matching repository schemas before server startup.
2. Re-running initialization does not drop databases or erase existing workflow data.
3. Frontend, history, matching, and internal worker run separately with readiness checks, resource budgets, and disruption protection.
4. Unauthorized clients cannot call Temporal APIs; approved clients use encrypted connections.
5. Production workloads tolerate a supported single-node disruption with spare schedulable capacity and database HA.

### US4 — Operate and recover the service (Priority: P2)
As an operator, I want alerts, capacity evidence, recovery procedures, and upgrade rehearsals so the service is supportable.

Independent test: future staging drills generate alerts, restore data into an isolated environment, and verify sequential schema/server upgrades.

Acceptance:
1. Dashboards expose service errors/latency, persistence errors/latency, task backlog, host health, and PostgreSQL saturation.
2. Backup restoration meets recorded RPO/RTO; database failover alone is not treated as disaster recovery.
3. Load tests justify shard count, replicas, connection limits, and throughput headroom before production.
4. Upgrade and rollback runbooks state schema compatibility constraints and avoid destructive rollback.

### Edge Cases
- rg-nexusflow already contains unrelated resources, or is missing.
- Name collisions for globally unique registry/storage names.
- Region lacks required zone redundancy, SKU, or quota.
- Private DNS or CI connectivity is missing; endpoints must not be opened publicly as an automatic fallback.
- AKS kubelet identity lacks registry access, including ACR RBAC/ABAC mode differences.
- Terraform state lock conflict, interrupted bootstrap, or partially completed provisioning.
- Schema job fails halfway, concurrent migration starts, or credentials rotate.
- Existing workflows, an old schema, or a mismatched image digest are detected.
- Pod drain and database failover occur during load; connection budgets exhaust.
- Plan artifacts or logs contain secrets; fork-origin CI must not receive privileged identities.

## Requirements

### Functional Requirements
- FR-001: Use Azure managed Kubernetes (AKS), create ACR, and use managed PostgreSQL Flexible Server.
- FR-002: Place directly managed Azure resources in rg-nexusflow. Explicitly document AKS-managed node-resource-group exceptions; do not force managed node resources into the cluster resource group.
- FR-003: Support explicit existing/create resource-group modes; do not delete shared rg-nexusflow.
- FR-004: Define private networking, DNS, nonoverlapping CIDRs, controlled egress, and operator/CI access.
- FR-005: Bootstrap protected remote Terraform state with locking and an explicit local-to-remote migration procedure.
- FR-006: Isolate Azure resource implementations from provider-neutral platform contracts and shared Kubernetes/Temporal configuration.
- FR-007: Compile Temporal server and SQL tools from a single approved commit of amitkohad/temporal.
- FR-008: Do not use prebuilt Temporal runtime images or download Temporal application binaries; omit the external CLI from the SQL-tools image.
- FR-009: Record source revision, compatible toolchain, schemas, provenance, SBOM, scan results, and immutable image digests.
- FR-010: Restrict image publishing to trusted release identities and separate it from build-only checks.
- FR-011: Use federated short-lived CI credentials and scoped Azure/Kubernetes permissions; provide private network access for privileged runners.
- FR-012: Configure separate persistence and advanced-visibility databases using supported PostgreSQL/version/plugin combinations.
- FR-013: Use serialized, explicit schema Jobs; initialization and upgrades must never drop existing databases.
- FR-014: Separate schema-owner and runtime roles, validate required runtime DML privileges, protect credentials, and verify certificate identity for database TLS.
- FR-015: Deploy frontend, history, matching, and internal worker separately; keep application worker/UI outside initial runtime scope.
- FR-016: Keep frontend private on its configured gRPC endpoint; restrict service and membership traffic.
- FR-017: Provide service/client TLS, internode TLS, authentication, authorization, and certificate rotation.
- FR-018: Define production replica/topology/disruption budgets, probes, graceful drain, resource requests/limits, and capacity reserves.
- FR-019: Choose and freeze history shard count before first cluster initialization; set retention and namespace limits from capacity requirements.
- FR-020: Provide metrics, dashboards, logs, alerts, retention, ownership, and an incident runbook.
- FR-021: Provide encrypted backups, PITR, restore rehearsal, availability-zone failure analysis, and an explicit regional-DR decision.
- FR-022: Document version compatibility, sequential upgrades, schema-before-server sequencing, and constrained rollback.
- FR-023: Define representative load, durability, visibility, failure, security, and recovery tests.
- FR-024: Validation must not apply Terraform, publish images, run migrations, register namespaces, or roll out workloads by default.
- FR-025: Require explicit later authorization for cloud execution; documentation generation is not deployment authorization.
- FR-026: Supply environment inputs, dry validation instructions, costs, task dependencies, ownership roles, and completion evidence.

### Key Entities
- Environment: subscription, tenant, location, resource-group mode, network ranges, capacity profile, retention and recovery objectives.
- Platform contract: cluster reference, registry endpoint, PostgreSQL endpoint, identity/secret references, private connectivity and observability endpoints.
- Release manifest: source commit, server version, toolchain, image digests, schema versions, compatibility evidence.
- Schema operation: release manifest, database, operation type, owner role, exclusive lock, result.
- Deployment: shared values plus Azure adapter values, release manifest, namespace, resource budgets.
- Readiness report: load results, fault drills, security checks, restore evidence, unresolved risks.

## Success Criteria
- SC-001: All 26 requirements map to stories and implementation tasks; every future execution task is clearly marked.
- SC-002: Build evidence proves that both Temporal runtime images originate from one approved commit.
- SC-003: Static checks pass without cloud mutation; a portability check detects Azure identifiers in shared configuration.
- SC-004: Staging durability and visibility scenarios pass after restarts and supported failover.
- SC-005: Restore and upgrade drills satisfy agreed recovery and service objectives.
- SC-006: Repeated infrastructure/schema operations are safe and do not delete shared or durable data.

## Inputs to resolve before execution
Subscription/tenant, Azure region, rg-nexusflow existence/ownership, environment classification, naming prefix, quotas, approved source commit/release, AKS/PostgreSQL versions and SKUs, CIDRs, runner/operator connectivity, DNS/certificate authority, client identities, expected workflow throughput/history size/search demand, availability target, RPO/RTO, budget and on-call owner.

Planning assumptions: approved toolchain/base OS images are allowed while Temporal application code is source-built; managed Azure services and platform agents are not built from this repository. Confirm this boundary before image implementation if "everything" also means toolchain/OS images. PostgreSQL-only visibility remains the initial requirement; measure search scalability before production.
