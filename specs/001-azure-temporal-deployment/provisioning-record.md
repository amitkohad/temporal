# Authorized staging provisioning

Date: 2026-10-09. Branch: `codex/001-azure-temporal-deployment`.

The user authorized provisioning prerequisites and continuing to provision resources as needed, then requested the next phase with parallel work where possible. This is standing authorization for the accepted low-cost staging design. Review saved Terraform plans before applying them. Keep Basic ACR's approved authenticated public endpoint, private Temporal/PostgreSQL, and the source-built Temporal policy. This authorization does not imply destructive teardown, a production rollout, or a new branch.

## Provisioned infrastructure

Target subscription: `aa228172-c4ae-4c29-bd05-dcdcebb70ff4`. Region: Central India. The existing `rg-nexusflow` is referenced by every root and remains outside Terraform resource ownership.

| State owner | Provisioned resources and profile |
|---|---|
| foundation/azure | `vnet-nexusflow-stg-ci` (`10.42.0.0/16`), four subnets, runner subnet NSG `nsg-nexusflow-stg-runner` and association. Runner inbound is denied; implicit subnet outbound access is disabled. |
| bootstrap/azure | `stnexusflowtf7c5841`, Standard LRS, TLS 1.2, shared keys/public network disabled; versioning, seven-day blob/container soft deletion, private bootstrap/infrastructure/platform containers and operator grants; state private endpoint and Blob DNS zone/link. |
| runner/azure | `vm-nexusflow-stg-ci-runner`, attended Ubuntu B1ms VM, managed identity, restricted state-container roles, NIC, Standard outbound public IP, independent inbound-denying NIC NSG and association. |
| environments/azure | Basic ACR `acrnexusflowstgci7c5841` with admin credentials disabled; private AKS `aks-nexusflow-stg-ci` 1.35.8 with one D2s_v5 system node; AKS identities/RBAC/registry pull role; PostgreSQL `psql-nexusflow-stg-ci-7c5841` 17, B1ms, 32 GiB, seven-day backups, no HA, Azure-selected zone 2; protected `temporal` and `temporal_visibility` databases; private PostgreSQL DNS; private RBAC/purge-protected Key Vault `kv-nxf-stg-ci-7c5841` and DNS/endpoint; runner Reader role; node NSG and association. |
| Azure-managed AKS node resource group | `rg-nexusflow-aks-stg-ci-nodes` contains AKS-owned node compute/disks, Standard load balancer/outbound IP and private API DNS resources. Do not duplicate ownership in another Terraform state. |

Subnet allocation: nodes `10.42.0.0/23`, PostgreSQL `10.42.2.0/27`, runner `10.42.3.0/27`, private endpoints `10.42.4.0/27`. PostgreSQL delegation and the Microsoft.Storage service endpoint are retained by the foundation. Kubernetes service and overlay ranges are `10.43.0.0/16` and `10.44.0.0/16`, with DNS `10.43.0.10`.

AKS API, PostgreSQL, state and Vault use private network paths. Basic ACR is the approved authenticated public exception. The runner outbound public IP and AKS load-balancer public outbound IP supply explicit egress and do not expose Temporal services. Paid Log Analytics ingestion defaults off. No NAT Gateway, Azure Firewall, VPN Gateway or Bastion was created.

## Egress and temporary permission status

The environment-owned node NSG is provisioned: Internet-bound TCP 443/80 and UDP 123 are allowed before other Internet traffic is denied. VNet outbound and Azure platform DNS/IMDS/agent behavior remain available. These are protocol/port restrictions, not FQDN filtering or prevention of transfers over permitted web ports.

The corresponding runner NIC NSG update is applied. Effective NSGs confirm its outbound restrictions and the independent foundation-owned subnet inbound denial; private connectivity checks passed afterward.

Automatic approval review rejected a resource-group-wide Network Contributor grant because it could modify the independent subnet boundary. The accepted temporary assignment is scoped only to `nsg-vm-nexusflow-stg-ci-runner`. The temporary assignment was removed after the reviewed NIC NSG update; future operations must also remove it immediately, including failure cleanup. Reader on `rg-nexusflow` remains read-only. No subscription Owner or role-administration capability is assigned to the runner. Future CI privileges and protected GitHub trust remain separate delivery work.

## State migration and ownership

The initial foundation/bootstrap local states had restricted Windows-user/SYSTEM ACLs and user-bound DPAPI backups under ignored `.deployment-local/state-backups`. Disk encryption is not verified; encrypted backups do not encrypt working local state. Initial bootstrap imported Azure's automatically created default Blob service into its existing owner before continuing; no duplicate child resource was created.

Migration receipts confirm the following initial private-backend handoffs. The serials below are migration snapshots; later remote applies may advance them.

| Root | Remote container / key | Migration lineage | Migration serial |
|---|---|---|---|
| bootstrap | bootstrap / nexusflow/stg/bootstrap.tfstate | b0182888-7efe-d3c6-c018-2c5d96aa4609 | 14 |
| foundation | infrastructure / nexusflow/stg/foundation.tfstate | f5eef910-4aec-2472-19f8-b2956afb9db2 | 8 |
| runner | infrastructure / nexusflow/stg/runner.tfstate | 5e69efb6-1523-db5e-97e3-b4e4bdbd9d3b | 9 |

Receipts were recorded at 09:52:50Z, 09:53:48Z and 09:54:22Z respectively. Initial handoff used authenticated management-plane transfer to the private VM, conditional Blob creation, lease exclusion and remote state checks. Frozen local copies must not be used for later local applies. Retain protected recovery backups. Each root has its own backend key; no states are combined.

Infrastructure state is migrated to `infrastructure / nexusflow/stg/infrastructure.tfstate`. Terraform backend initialization and state pulls passed for all four roots. Frozen local copies remain recovery snapshots, not authoritative state. The platform root validates a nonsecret handoff and has not deployed Kubernetes resources.

## Implementation and validation boundary

Phase 3 implements T017–T031. Terraform mock plans verify declared ownership, profile, security and input gates; they do not establish private endpoint access, claims, restored data, image pulls or running Temporal behavior. All 60 Terraform mock tests and seven Python migration/archive safety tests passed, with formatting and validation across 14 roots.

The runner module's three mock tests and Terraform validation passed after its outbound protocol rules were added. PowerShell/Python probe syntax and Bash helper syntax passed. Mocked probe execution verified the expected competing-lease rejection and cleanup on an unexpectedly successful competing acquire without printing token values. These checks do not replace live Blob lease verification.

Live corrective implementation included a distinct PostgreSQL private DNS prefix because Azure rejects a zone equal to the server hostname, and preserving Azure-selected/failover PostgreSQL zone placement. Foundation state must retain the Microsoft.Storage service endpoint configured for the delegated database subnet. The initial foundation/bootstrap verification recorded clean plans before this phase's resource expansion; fresh final plans are required.

No Go source changed. Required `make lint-code-fast` was attempted but `make` is unavailable on this host. All work remains on the authoritative branch; no branch creation or merge occurred.

## Explicit remaining checks and runtime work

Infrastructure execution evidence is recorded below. Authenticated registry image pulls require a source-built image in Phase 4; anonymous registry access was verified denied with HTTP 401. Runtime database login/TLS, workload policies and recovery drills remain later verification tasks.

No Temporal application images have been built or pushed, no Temporal schemas initialized, and no Temporal namespaces/service pods/application workers deployed by this phase. GitHub CI, JIT registration and Azure federation are not enabled. Certificates, separate database runtime/migration roles, renewable token or reviewed password integration, schema migration jobs, workload network policies, source-build provenance, restore drills and production recovery decisions remain later tasks.

Use the Free AKS control-plane tier, minimal staging compute and attended stop/start where practical. Retained disks, static IPs, private endpoints, DNS, ACR and PostgreSQL storage still incur charges; a deallocated VM is not completely free. PostgreSQL restarts automatically after seven days stopped. No spending cap or credit eligibility is assumed.

T078 staging infrastructure execution is complete. T077 remains partial for GitHub federation, and T079 for authenticated source-image pulls. Historical Phase 1/2 no-provisioning statements describe the earlier authorization boundary; this record reflects the current standing authorization.

## Final verification and cost-control evidence

Terraform private backend initialization and state pulls passed: bootstrap serial 14 / eight entries, foundation serial 8 / five entries, runner serial 10 / six entries, infrastructure serial 38 / 25 entries. All preserved their migration lineage. Temporary private-operation configuration and plans were removed from the runner after verification.
Verified final evidence: 60 Terraform mock tests across 14 roots, seven Python migration/archive safety tests, formatting/validation and whitespace checks passed. Final live infrastructure plan returned exit code 0. Foundation plan through its private backend returned no changes. Effective runner NSGs include independent inbound denials and Internet TCP 443/80 plus UDP 123 allow rules ahead of the deny rule. State probes confirmed all three containers, exclusive lease contention (HTTP 409), private Blob DNS 10.42.4.4 and private PostgreSQL/Vault/AKS TCP reachability. TLS-verified AKS managed-identity access returned one Ready node; Vault metadata access returned zero secrets. The temporary NIC-NSG Network Contributor assignment was removed and read-only ARM verification confirmed its absence.

Infrastructure migration: key `nexusflow/stg/infrastructure.tfstate`, lineage `8fd76557-698c-6196-7e05-b13528b08a16`, serial 38, 25 resource entries. A nonsecret platform handoff was generated into ignored local inputs and its provider-neutral plan validated without application resources.

Observed final cost-control state: AKS power `Stopped` with provisioning `Succeeded`; PostgreSQL `Stopped`; attended runner `PowerState/deallocated`. Supported stop/deallocation commands all completed successfully. Restart the runner through Azure's management plane when private operations are needed; start AKS/PostgreSQL before the later runtime phase. Retained storage/network/registry charges continue. PostgreSQL automatically restarts after seven days, so revisit its state when continuing work; no recurring automation was created.

Phase 3 implementation T017–T031 and staging infrastructure execution T078 are complete. Phase 4 source builds are next. No new branch, merge, application build/publish, schema initialization or Temporal deployment occurred.