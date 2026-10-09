# Infrastructure ownership and operation

All deployment work stays on `codex/001-azure-temporal-deployment`. The user has authorized provisioning the accepted staging design as needed. Review saved plans before applying them; do not create branches or merge into main.

## State and ownership

| Root | Owned resources | Remote container/key |
|---|---|---|
| foundation/azure | VNet, four subnets, runner subnet NSG and association | infrastructure / nexusflow/stg/foundation.tfstate |
| bootstrap/azure | State storage, private containers, DNS/endpoint, bootstrap grants, optional CI trust | bootstrap / nexusflow/stg/bootstrap.tfstate |
| runner/azure | Attended runner VM, NIC, outbound IP, NIC NSG, state grants | infrastructure / nexusflow/stg/runner.tfstate |
| environments/azure | AKS node subnet NSG and association, ACR, AKS identities/cluster/roles, PostgreSQL/DNS/databases, Vault/DNS/endpoint/roles, optional telemetry | infrastructure / nexusflow/stg/infrastructure.tfstate |
| platform | Nonsecret handoff contract now; Kubernetes resources in later implementation | platform / nexusflow/stg/platform.tfstate |

Every root references existing `rg-nexusflow`; none owns it. The foundation root is the sole owner of VNet/subnets and the runner subnet NSG. The environment root owns the separate AKS node NSG and subnet association. The runner root owns its NIC NSG and association. Consume its IDs, never recreate them in the infrastructure state. AKS owns the contents of `rg-nexusflow-aks-stg-ci-nodes`, including its private API DNS zone, VM scale set, disks and load balancer/outbound IP. Do not add those resources to a second Terraform state or operate AKS-managed VM scale sets directly.

The PostgreSQL subnet declares its Microsoft.Storage service endpoint because Azure configures that dependency when provisioning the first server. Preserve that endpoint; a later foundation plan must not remove it as unrecorded drift.

## Bootstrap and normal execution

Each initial root starts with protected local state until the private operator path works. Backend blocks are activated through ignored `backend.local.tf` after migration. `environments/azure/backend.tf.example` is a template, not an active remote backend; this avoids the first-backend dependency cycle.

Run `scripts/deployment/protect-local-state.ps1` only when no state operation is active. On this Windows host it produces user-bound DPAPI backups and restricts local state/input/plan ACLs. Keep encrypted backups outside Git and retain recovery access to the originating Windows account.

`migrate-private-state.ps1 -Root <bootstrap|foundation|runner|infrastructure>` seeds an empty backend from the attended VM using managed identity. The state travels over authenticated Azure management-plane TLS; it is never printed. The helper conditionally creates a blob with If-None-Match, refuses a different existing lineage/serial/content, acquires a Blob lease and verifies resources/outputs before recording a receipt. Identical content is a safe resume. It checks the local source hash and operation lock before freezing the local copy as `.tfstate.migrated` and activating a remote backend block. The remote root is authoritative after verification; never continue a local apply from the frozen copy. This is an explicit initial backend seeding procedure, not an unconditional force-copy or state push.

Run `verify-private-backends.sh` through the attended runner to initialize the Azure backend and pull each migrated state with Terraform. It verifies nonempty state and reports only lineage, serial and resource count. Terraform 1.10.5 Linux download has its SHA-256 pinned from the official release checksum list. Temporary state files are restricted and removed.

Normal infrastructure operations run from a private path using the correct remote container/key. The runner has container-scoped state permissions and read-only ARM access for verification; it cannot assign Azure roles or provision arbitrary resources. The human Owner performed initial provisioning. Future CI write roles and separate role-assignment authority must be resolved in the delivery phase. Never silently promote the runner to subscription Owner. For the attended NIC NSG update, temporary Network Contributor is restricted to `nsg-vm-nexusflow-stg-ci-runner`, then removed after apply and verification, with failure cleanup. The runner subnet NSG belongs to the foundation and remains outside that assignment's scope. An attempted resource-group-wide Network Contributor assignment was rejected by automatic approval review because it could change the independent subnet boundary; the narrower NSG-only assignment is the accepted recovery path. Reader on the resource group remains read-only after the temporary grant is removed.

## Data and secrets

PostgreSQL 17 staging uses B1ms, 32 GiB, seven-day backups and no HA. Two databases are protected against Terraform deletion/replacement. Server initialization creates no Temporal schemas. `BTREE_GIN` is allowlisted for the visibility schema. DNS uses a unique `private-` prefix: Azure rejects a zone equal to the server hostname.

Provisioning uses Entra administration and no password values in Terraform. Before schema/runtime work, implement application runtime versus migration roles and either an audited renewable token path or externally generated/rotated passwords with Key Vault handoff. Do not assume a static Entra token can serve as a permanent Temporal database password. Azure backup settings do not prove restoration; the recovery drill remains a later task.

Vault is private, RBAC-enabled, purge-protected and exports references only. Certificate issuer, logical secret names, lifetimes and rotation are defined in subsequent runtime tasks; this phase does not fabricate certificates or secret values.

## Network boundary

The environment root provisions node egress rules that permit Internet TCP 443/80 and UDP 123 and deny other Internet protocols. The runner NIC uses the same rules after its reviewed update is applied. Foundation subnets disable implicit outbound access; the AKS load balancer and runner public IP provide separate explicit outbound paths. These free NSG controls preserve VNet and Azure platform access and do not implement FQDN filtering or prevent HTTPS/HTTP exfiltration. See [network ownership and flows](network.md) for operation and verification limits.

## Cost and telemetry

Staging uses Basic ACR, AKS Free control plane and one shared D2s_v5 node. Platform metrics/activity logs remain available. Paid Log Analytics/diagnostic ingestion defaults off; the optional observability adapter supports explicit categories and owner action groups. No spending cap or fictional alert recipient is created.

Use an attended runner, deallocate it when idle, and stop empty AKS/PostgreSQL compute between implementation sessions where practical. Retained disks, IPs, private endpoints, DNS, ACR, database storage and vault operations can still incur charges. PostgreSQL automatically starts after seven days stopped; a stopped server is not a permanent free resource. Use supported AKS stop/start APIs, not direct node VM operations.

## Recovery and teardown

A partial apply is not a reason to recreate durable resources. Inspect live resource and state, import resources created outside state into their sole owner, and review a new plan. The initial default Blob service needed import because Azure creates it automatically. Correcting an unused DNS zone is distinct from replacing a database.

Do not destroy the shared group, databases, backend or vault to repair failures. Database/server, state containers/account, VNet and Vault have lifecycle protection where applicable; Azure administrator deletion remains possible. Deleting or rebuilding the private runner must preserve a recovery path to state. Keep a deallocated runner available for restart rather than destroying the only management-plane private access path.