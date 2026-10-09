# Azure staging environment

Decision date: 2026-10-09. Status: selected staging inputs; user authorization now permits provisioning as needed. See the provisioning record for current resources.

## Branch policy
Use codex/001-azure-temporal-deployment for all deployment implementation. Do not create another branch or merge into main. This policy applies to future phases and release workflow branch filters.

## Account and ownership
Read-only Azure CLI inventory verified:
- Subscription: Visual Studio Enterprise, aa228172-c4ae-4c29-bd05-dcdcebb70ff4, Enabled.
- Tenant: 48d2ccb2-9e24-49cc-921b-89962ed5f85f.
- Resource group: rg-nexusflow, existing, Central India (centralindia).
- Resource group has no resources at inspection; managedBy is null and tags are empty.
- Only this subscription was returned by the active account's subscription listing.

Use resource_group_mode=existing. Do not create, destroy, or claim Terraform ownership of the resource group. Directly managed resources go in rg-nexusflow; AKS-managed node resources use a distinct Azure-managed node resource group. Account metadata does not prove permission to create resources, assign roles or configure Entra federation; check those before execution.

## Classification and names
The user selected a staging pilot and minimum cost, with no spending cap. No production availability commitment applies. Central India is selected from the existing group's location; the group location alone does not require colocated resources, but keeping the pilot in one region reduces complexity.

| Resource | Selected name |
|---|---|
| Environment | stg |
| Logical prefix | nexusflow |
| AKS | aks-nexusflow-stg-ci |
| Managed node group | rg-nexusflow-aks-stg-ci-nodes |
| ACR | acrnexusflowstgci7c5841 |
| PostgreSQL | psql-nexusflow-stg-ci-7c5841 |
| State storage | stnexusflowtf7c5841 |
| Key Vault | kv-nxf-stg-ci-7c5841 |
| Temporal namespace | nexusflow-staging |

ACR and storage name availability returned true. Names are not reserved; recheck before creation. PostgreSQL and Key Vault name availability remain execution preflight checks. Suffix 7c5841 is a nonsecret stable naming discriminator, not a credential.

## Network allocation
| Purpose | CIDR |
|---|---|
| VNet | 10.42.0.0/16 |
| AKS nodes | 10.42.0.0/23 |
| PostgreSQL delegated subnet | 10.42.2.0/27 |
| Ephemeral runner | 10.42.3.0/27 |
| Private endpoints | 10.42.4.0/27 |
| Kubernetes services | 10.43.0.0/16 |
| Service DNS | 10.43.0.10 |
| Azure CNI Overlay pods | 10.44.0.0/16 |

Observed subscription VNet ranges: 10.0.0.0/16, 10.1.0.0/16, 10.30.0.0/16. Proposed node/service/pod ranges do not overlap them or each other. No peerings, on-premises routes or cross-subscription networks were inspected; validate before introducing connectivity. Overlay networking is a design selection, not a configured cluster.

## Isolation
Separate bootstrap, infrastructure and platform state keys under nexusflow/stg/. No production resources share staging state or database credentials. Production requires a separate profile and a production-capable subscription, never silently promoted from this dev/test profile.

Related decisions: [capacity](capacity.md), [source builds](source-build.md), [access](access.md), [recovery](recovery.md).
