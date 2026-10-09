# Authorized prerequisite provisioning

Date: 2026-10-09. Branch: `codex/001-azure-temporal-deployment`.

The user authorized provisioning existing prerequisites and continuing to provision resources as needed. This is standing authorization for the accepted staging design; review saved Terraform plans before applying them. Preserve the lowest practical cost, Basic ACR exception, private Temporal/PostgreSQL and source-built application policy. This authorization does not imply destructive teardown.

## Verified live resources

Target: subscription `aa228172-c4ae-4c29-bd05-dcdcebb70ff4`, resource group `rg-nexusflow`, Central India. Existing resource-group ownership is retained. The signed-in bootstrap principal has inherited Owner access; state roles are narrower container-scoped Blob Data Contributor grants.

- VNet `vnet-nexusflow-stg-ci`, `10.42.0.0/16`.
- Four subnets: nodes `10.42.0.0/23`, delegated PostgreSQL `10.42.2.0/27`, runner `10.42.3.0/27`, private endpoints `10.42.4.0/27`. All explicitly disable default outbound access.
- Runner NSG `nsg-nexusflow-stg-runner` and subnet association; inbound traffic is denied.
- State account `stnexusflowtf7c5841`, Standard LRS, TLS 1.2, public network and shared keys disabled.
- Blob versioning and seven-day blob/container soft deletion; private containers `bootstrap`, `infrastructure`, `platform` and scoped operator roles.
- Approved private endpoint `pe-nexusflow-state`, private DNS zone `privatelink.blob.core.windows.net` and completed VNet link. Azure owns the endpoint NIC.

Foundation apply: 7 added, no changes/deletions. Initial bootstrap created four managed resources before discovering Azure automatically creates its default Blob service. Imported that existing child into the same bootstrap state; reviewed continuation plan applied six additions and one update, with no deletion. The runbook now documents account-first bootstrap and import for fresh accounts.

## State ownership and checks

`foundation/azure` exclusively owns network resources; `bootstrap/azure` owns state resources. Neither owns the existing resource group. Current authoritative states remain local and excluded from Git. State, plan and local input ACLs are restricted to the current Windows user and SYSTEM; user-bound DPAPI backups are under ignored `.deployment-local/state-backups`. The backup script successfully protected both roots after provisioning. Disk encryption is not verified; encrypted backups do not encrypt the working state files.

All 27 Terraform mocked tests passed, including explicit private subnets, delegated PostgreSQL, inbound runner isolation, state access and versioning, branch-bound federation and resource-group ownership. Formatting and Terraform validation passed. Post-apply live plans for both roots returned exit code 0 with no changes. ARM reads confirmed versioning, seven-day deletion protection, disabled public/shared-key access, approved private endpoint and completed DNS link. No Go source changed; `make lint-code-fast` is unavailable because make is absent on this host.

## Next dependencies

An attended VNet-connected runner/operator route is still required to test private Blob data-plane access and locking, and migrate local state. Use bootstrap key `nexusflow/stg/bootstrap.tfstate` and infrastructure-container foundation key `nexusflow/stg/foundation.tfstate`; do not reuse the later infrastructure key. Do not report backend migration or private data-plane access as verified yet.

The four subnets have no implicit internet egress. AKS requires explicit Standard Load Balancer outbound configuration; the on-demand runner needs an explicit outbound path. Complete these with the runner/AKS implementation. No permanent NAT, VPN gateway, Bastion or compute was provisioned. Storage, private endpoint and DNS incur charges; no free-credit eligibility is assumed.

AKS, ACR, PostgreSQL, Key Vault, monitoring, runner and GitHub OIDC are pending their implementation/dependencies. Federation stays disabled until custom claims and protected environment are verified. No Temporal images, schemas or runtime workloads have been deployed.

T017/T018/T019 and T077/T078/T079 remain partial; do not mark complete until their routing, DNS, access and migration evidence exists. Historical Phase 1/2 records describe the authorization and checks at that time; this record supersedes their earlier no-provisioning restriction.