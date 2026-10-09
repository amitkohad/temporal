# Phase 3 implementation evidence

Date: 2026-10-09
Branch: codex/001-azure-temporal-deployment
Status: T017–T031 implementation complete. Provisioning is authorized by the user's standing instruction; execution acceptance is tracked separately in T077–T079 and the provisioning record.

## Delivered

| Tasks | Implementation evidence |
|---|---|
| T017–T018 | Foundation owns one VNet and four isolated subnets, PostgreSQL delegation and Microsoft.Storage service endpoint. PostgreSQL owns its distinct private DNS zone and VNet link. Network and dependency documentation describes DNS, storage, HA and private-route requirements. |
| T019 | Explicit AKS Standard load-balancer SNAT and independent runner outbound IP; implicit subnet outbound access disabled. Node NSG permits Internet TCP 80/443 and UDP 123, then denies other Internet traffic. Runner denies inbound traffic. Dependency ports/endpoints are documented. |
| T020 | Basic authenticated public ACR with admin credentials off, scoped registry permissions, and a private Premium option with DNS/endpoint integration. |
| T021–T023 | Private AKS API without public FQDN, Entra and Azure RBAC, local accounts disabled, OIDC/workload identity, VNet-scoped control-plane permissions, kubelet identity and registry pull grant. Staging shares one system node; production declares separate system/user capacity, zones, autoscale bounds and surge. |
| T024–T025 | PostgreSQL 17 default B1ms/32 GiB, seven-day backups, no staging HA, configurable non-burstable HA, private delegated network and Entra-only administration. Two distinct protected databases; BTREE_GIN allowlisting for visibility. Server/database destruction guards and Azure-selected/failover zone preservation. |
| T026 | Private Standard Key Vault with RBAC, private DNS/endpoint, soft delete, purge protection and destruction guard. Scoped reader/operator roles and reference-only outputs. Logical runtime credentials, certificates and rotation are explicit later-phase handoffs. |
| T027 | Optional paid Log Analytics with retention/ingestion controls, explicit supported diagnostic categories, scoped metric alerts requiring existing owner action groups. Staging defaults off; no spending cap or fabricated notification recipient. |
| T028 | Independently bootstrappable runner root/module with attended private-inbound VM, managed identity and scoped state access. JIT helper consumes short-lived configuration through stdin, executes one job in restricted temporary storage and cleans up. Live GitHub package installation/registration is deferred to delivery work. |
| T029 | Environment composition consumes existing foundation IDs, joins module dependencies, and exports actual nonsecret Azure references. Examples preserve staging cost choices and production input gates. |
| T030 | Separate provider-neutral platform root validates a small nonsecret handoff. No Kubernetes provider or application resources in the infrastructure plan; no admin kubeconfig or full infrastructure state is handed to application pods. |
| T031 | Ownership, import, partial apply, state migration and teardown runbook identifies each root and the Azure-managed AKS node resource group. Existing shared rg-nexusflow is referenced, never owned. |

## Provisioned profile and verification boundary

The parent provisioning operation has created private AKS 1.35.8 with one D2s_v5 node, PostgreSQL 17 B1ms/32 GiB in Azure-selected zone 2, two protected databases, private Key Vault, Basic ACR with admin credentials disabled, and an attended B1ms runner with denied inbound connectivity. The node NSG is applied. These are infrastructure resources; Temporal schemas, service pods, namespaces and images have not been deployed by this phase.

Bootstrap, foundation and runner states have been migrated to their separate private backend keys. Infrastructure state migration completed after a clean live plan. Final private-route/authorization/egress checks passed and the temporary NIC-NSG write grant was removed. T078 is complete; T077 remains partial for GitHub federation and T079 for authenticated source-image pulls. Consult [provisioning-record.md](provisioning-record.md) for current live status.

## Validation

All 60 Terraform mocked tests passed across 14 roots, with formatting and validation successful. All seven offline migration/archive tests passed. Database module validation and five tests, Key Vault validation and two tests, and observability validation and six tests passed independently. These mock plans verify declared configuration; they do not establish live token claims, private routes, image pulls, workload behavior, restore timing or alert delivery.

Two live issues produced corrective implementation evidence: Azure rejects a PostgreSQL DNS zone equal to the server FQDN, so the module uses a distinct private- prefix with a regression assertion. Azure assigns the PostgreSQL zone and may change it after HA failover, so the server lifecycle preserves zone and standby-zone placement, following the pinned provider's guidance.

Required make lint-code-fast was attempted but make is unavailable on this host. No Go source changed. All work remains on the existing authoritative branch; no branch creation, merge or deployment-source changes are part of this record.

## Remaining runtime and production decisions

The node NSG filters protocols/ports rather than FQDNs; permitted web traffic remains broadly reachable. There is no Firewall/NAT Gateway/domain proxy in low-cost staging. Runtime NetworkPolicies and production egress architecture remain later requirements. Foundation routing does not prove workload policy isolation.

Entra-only PostgreSQL avoids password values in Terraform. Before Temporal deployment, implement renewable database token authentication or an explicitly reviewed password configuration with credentials generated and rotated through the private Key Vault data plane. A fixed Entra token cannot serve as a durable Temporal password. Separate runtime/migration roles, TLS verification, schema jobs and certificate rotation remain later tasks.

Backup configuration does not prove restore readiness. Production HA capacity, recovery objectives/owners, certificate issuer and delivery identity trust remain acceptance gates. No production readiness claim is made by this infrastructure implementation.

## Entry points

- [Task backlog](tasks.md)
- [Infrastructure ownership runbook](../../docs/deployment/infrastructure.md)
- [Network and dependency design](../../docs/deployment/network.md)
- [Runner runbook](../../docs/deployment/runner.md)
- [Platform handoff](../../infra/terraform/platform/README.md)
- [Validation script](../../scripts/deployment/validate-terraform.ps1)