# Research and decisions

Date: 2026-10-09
Inspected local source commit: 4b74f358be4f58bc1d1841548b25d23a1210761e
This is an inspection baseline, not an approved production release.

## Repository evidence
- AGENTS.md and .github/copilot-instructions.md reviewed.
- No .specify workspace, feature specs, or Terraform roots were present.
- go.mod declares Go 1.27.0. Verify an approved, available matching toolchain before builds; do not silently downgrade the module.
- Makefile provides temporal-server and temporal-sql-tool targets. Preserve its build tags and version metadata.
- docker/targets/server.Dockerfile packages an already built binary and runs as UID 1000.
- docker/targets/admin-tools.Dockerfile also requires a temporal CLI binary.
- .github/actions/build-docker-images/action.yml downloads that CLI. Reusing this action unchanged would violate source-only application builds.
- docker/docker-bake.hcl uses an Alpine tag, upstream source labels, and server/admin-tools targets. Future fork deployment should record our source URL and reviewed base provenance.
- schema/postgresql/v12/version.go declares persistence schema 1.19 and visibility schema 1.14 at the inspected commit.
- Makefile install-schema-postgresql12 drops both databases. Never run that target for hosted persistence.
- Current build-and-publish workflow targets main/cloud/feature/release and publishes to Docker Hub. A separate Azure delivery workflow must support the codex branch convention and keep build-only and publishing triggers distinct.

## Decisions
1. Use AKS and PostgreSQL Flexible Server. Create ACR because none exists. Use rg-nexusflow as the parent resource group with explicit existing/create mode; allow Azure-managed node resource group.
2. Terraform is a portable orchestration language, not a provider-independent resource API. Implement Azure adapters with azurerm (and azuread only where necessary); define stable inputs/outputs. Shared Kubernetes configuration uses kubernetes/helm interfaces and a cloud-neutral values contract. Other cloud adapters are future work.
3. Separate bootstrap, infrastructure, and application roots/state. Avoid configuring a Kubernetes provider against a cluster created in the same initial plan.
4. Plan private AKS, private ACR (SKU supporting Private Link), private Key Vault/storage, and PostgreSQL delegated-subnet VNet integration. Do not mix PostgreSQL delegated-subnet mode with Private Link casually; reassess supported provider/service options at implementation.
5. Provide an ephemeral VNet-connected delivery runner independent of Temporal readiness. Bootstrap via authorized management-plane provisioning; then use private data-plane DNS/routes. No public endpoint fallback.
6. Build a minimal SQL-tools image with temporal-sql-tool and matching schema directories. Exclude CLI, Cassandra, and Elasticsearch tools from initial Azure scope. Source-built test-worker code can use repository SDK dependencies; Web UI requires separate source.
7. Use PostgreSQL for both stores initially. Validate advanced visibility queries and load. A postgres12 plugin name denotes a compatibility implementation, not a requirement to deploy obsolete PostgreSQL 12.
8. Schema migration is an explicit release stage with serialization, limited privileges, version checks, safe retry, backups and audit evidence. It is not a server startup side effect.
9. Use OIDC federation for CI, managed identities for Azure access, and Kubernetes service-account workload identity where appropriate. Registry role choice must match RBAC/ABAC mode.
10. Remote state stores sensitive data even when outputs are marked sensitive. Protect storage, state/plan artifacts, access, leases, versioning, and break-glass recovery.
11. Production topology and shard count are workload-dependent. No promised SLA follows from a fixed replica number. Database HA is not regional DR.
12. Generate Spec Kit-shaped artifacts directly from its published workflow/templates. Do not install a CLI or add generated agent commands without need; no claim that slash commands were executed.

## Sources
- [GitHub Spec Kit workflow](https://github.com/github/spec-kit): constitution, specify, plan, tasks, implement, converge; stop here before implementation.
- [Spec template](https://github.com/github/spec-kit/blob/main/templates/spec-template.md)
- [Plan template](https://github.com/github/spec-kit/blob/main/templates/plan-template.md)
- [Tasks template](https://github.com/github/spec-kit/blob/main/templates/tasks-template.md)
- [Temporal deployment](https://docs.temporal.io/self-hosted-guide/deployment): private hosts, Helm compatibility, version-matched schema tools.
- [Temporal production checklist](https://docs.temporal.io/self-hosted-guide/production-checklist): capacity testing, monitoring, shard constraints, sequential upgrades.
- [Temporal visibility](https://docs.temporal.io/self-hosted-guide/visibility): PostgreSQL advanced visibility support; measure suitability under intended load.
- [Private AKS](https://learn.microsoft.com/en-us/azure/aks/private-clusters): DNS, private access, managed identities and node resource group.
- [Private AKS connectivity](https://learn.microsoft.com/en-us/azure/aks/private-cluster-connect)
- [ACR role modes](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-abac-repository-permissions)
- [PostgreSQL private networking](https://learn.microsoft.com/en-us/azure/postgresql/network/concepts-networking-private)
- [Terraform Azure backend](https://developer.hashicorp.com/terraform/language/backend/azurerm): locking, Entra authentication and federation.
- [Terraform sensitive data](https://developer.hashicorp.com/terraform/language/manage-sensitive-data)

Version pins, SKUs and availability must be rechecked at implementation; no Azure account inventory or resource inspection was performed.
