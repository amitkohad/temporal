# Protected state and identity bootstrap

The user has authorized provisioning resources as needed, including existing prerequisites. Review concrete plans before applying them; repeat permission is not required within the accepted staging design. See [provisioning record](../../specs/001-azure-temporal-deployment/provisioning-record.md) for live status.

## State ownership
The Azure environment references existing rg-nexusflow by default and never owns unrelated resources. Explicit create mode owns only that named group and has prevent_destroy. Only one state may use create mode; all other roots must reference the existing group. Never declare the same group as owned in bootstrap and infrastructure states.
The state storage account, blob service and three private containers also have prevent_destroy. Versioning and seven-day blob/container soft deletion are enabled. Storage uses Standard LRS to minimize staging cost, HTTPS/TLS 1.2, encrypted blobs, Entra authentication only, disabled shared keys and disabled public network access.
Each root has a separate container/key: bootstrap, infrastructure and platform. Azure Blob leases provide remote state locking; do not replace this with an application lock. A registry publisher has no state role.

Terraform lifecycle guards only work while the resource remains in configuration. They do not prevent deletion by an Azure administrator or forceful state/config changes. Retain reviewed ownership, restricted Azure privileges and backups; state is confidential even without sensitive outputs.

## Avoiding the first-backend dependency cycle
1. Resolve the Phase 1 bootstrap approver and the actual state operator object IDs. Review network ranges and permissions.
2. Use foundation/azure to create the VNet and four private subnets with protected local state. This root is their sole owner. Establish an attended private runner/operator route before backend migration.
3. Supply that existing subnet/VNet to bootstrap/azure. The bootstrap root deliberately starts without a backend block and stores its initial state locally.
4. On a fresh subscription, review and apply an account-only plan using -target=azapi_resource.state, then import the automatically created blobServices/default child into azapi_resource.blob_service. Use the actual account ARM ID with /blobServices/default appended. Azure creates this child automatically; a direct attempt to create it fails. This targeted step is only for first bootstrap. Review a new complete plan, then apply protection settings, containers, DNS/endpoint and roles. On existing managed state, use a normal complete plan. Container management does not require public Blob access.
5. Verify private Blob DNS/routing from the operator/runner and allow time for RBAC propagation. Verify the operator has container-scoped Storage Blob Data Contributor.
6. Copy backend.tf.example to the ignored backend.local.tf. Copy backend.tfbackend.example to an ignored local backend configuration; no credentials belong in it.
7. The implemented attended procedure uses migrate-private-state.ps1 to conditionally seed empty backend blobs and verify content under a lease. It freezes local copies only after verification. See infrastructure.md. Standard reviewed init -migrate-state remains an alternative from a private access path; never use blind -force-copy.
8. Verify serial, lineage and resource addresses on the remote copy. Back up state securely, then remove redundant local state after confirmed migration.
9. Migrate the separately owned network-foundation state into its own approved container/key before normal infrastructure composition proceeds. Never create the same foundation resources in a second state. Foundation uses infrastructure container key nexusflow/stg/foundation.tfstate, distinct from infrastructure.tfstate.

No infrastructure root can use the private backend before its access path exists. The final environments/azure root declares an Azure backend, but this change uses only init -backend=false for validation. Example placeholders are not live inputs; use the provisioned network IDs and verified operator object ID in ignored local inputs.

## Local state and artifact handling
Use restricted file permissions and encrypted backups for initial state. On Windows run scripts/deployment/protect-local-state.ps1 after each completed bootstrap/foundation operation. It restricts state, plan and input ACLs to the current user and SYSTEM, and creates user-bound DPAPI backups under ignored .deployment-local/state-backups. Keep the authoritative local files until private-route migration succeeds. Disk encryption has not been verified; these files must stay local until the private runner handoff. State, plans, .terraform, local tfvars, backend configuration and dotenv files are ignored. Git ignore does not encrypt data or remove a previously committed secret; inspect before publishing.
Supply credentials through Azure CLI/managed identity or OIDC environment variables; never commit storage keys or ARM client secrets. After migration use Entra backend authentication; use_oidc=true is selected only in an OIDC-enabled job.
Remote state access should be container-scoped. Infrastructure output handoff must export only references; do not give application pods remote state access.

## GitHub OIDC prerequisite
Default GitHub subjects bind an environment OR a branch, not both. This bootstrap therefore requires an explicitly customized subject containing immutable repository/owner IDs, environment and ref.
For this repository, the selected ordered claim keys are:
repository_id, repository_owner_id, environment, ref.
Expected subject:
repository_id:1411347811:repository_owner_id:19859979:environment:staging:ref:refs/heads/codex/001-azure-temporal-deployment

Before enabling federation, an authorized repository administrator must verify those immutable IDs, configure the custom OIDC subject, protect the staging environment, restrict its deployment branch to codex/001-azure-temporal-deployment and require appropriate reviewers. Jobs must declare environment=staging and request audience api://AzureADTokenExchange.
Do not enable federation until an actual emitted subject matches. Do not log JWTs; inspect claims through a safe diagnostic. A mismatched subject fails closed; this implementation has not created or altered GitHub settings.
No release workflow is introduced in Phase 2. Default enable_github_federation=false creates no CI identities/trust.

## Permission matrix
| Principal | Declared privilege | Remaining scope |
|---|---|---|
| Supplied state operators | Blob Data Contributor on each state container | Human owner/approved private access must be supplied |
| Infrastructure identity | Contributor on rg-nexusflow; state access to infrastructure container | No User Access Administrator or Owner; role assignment operations need approved separate bootstrap authority |
| Deployment identity | State access to platform container | AKS/Kubernetes permissions added at the cluster scope in later phases |
| Registry writer | No state access and no resource-group Contributor | ACR write role added at registry scope in phase 3 |

Only the human bootstrap principal has bootstrap-container access here. OIDC CI jobs cannot modify bootstrap state through a granted state role. Contributor does not grant permission to assign Azure roles; do not claim infrastructure CI can complete all future identity operations without separate delegated authorization.

## Partial failure, locking and recovery
- Stop on failed provisioning, RBAC propagation, DNS or migration; never rerun apply automatically.
- Preserve the most recent authoritative state and serial. If remote migration is interrupted, compare protected local/remote copies before resuming.
- If a resource was created but not recorded, inspect it read-only and import it into the correct state with operator review; never recreate blindly.
- Unlock only after proving no operation holds the lease and after operator authorization. Never automatically force-unlock.
- Recover accidental state changes from retained blob versions and revalidate resource addresses; restoring an old state does not restore infrastructure.
- Do not destroy storage, containers, rg-nexusflow or workflow databases to repair state.

## Evidence required before execution
Accepted input/profile, explicit cloud-execution authorization, scoped roles, resolved operator IDs, existing network/runner access, tested GitHub claims if federation is enabled, reviewed plans and backup/migration recovery owner.

Sources: [Azure backend authentication and locking](https://developer.hashicorp.com/terraform/language/backend/azurerm), [GitHub OIDC claims](https://docs.github.com/en/actions/reference/security/oidc), [Azure storage ARM schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.storage/2023-05-01/storageaccounts).
