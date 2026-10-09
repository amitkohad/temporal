# Temporal Terraform foundation

Private network foundation and state bootstrap are provisioned under standing user authorization. See the provisioning record for verified status. AKS, registry, PostgreSQL and Temporal follow in later steps.

## Layout
- modules/contracts: provider-neutral typed inputs, IPv4 boundary checks and production gates.
- modules/azure/resource-group: explicit existing/create ownership of rg-nexusflow.
- environments/azure: environment contract and Azure scope; phase 3 will add actual resource modules.
- foundation/azure: separately owned private VNet, subnets and runner inbound isolation; starts with local state.
- bootstrap/azure: private state storage, separate containers, private DNS/endpoint and optional federated identities.
- tests: test catalogue; executable test suites live under their configuration roots.

Environment outputs are validated input contracts and scope metadata. No fabricated cluster/database endpoints, credentials or kubeconfig are exported. Actual platform outputs will be wired after phase 3 creates those resources.

## Tooling
Terraform >=1.10.5,<1.11.0; AzureRM 4.50.0; AzAPI 2.4.0. Pins are deliberately reviewed baselines, not a claim that they are the newest versions. AzAPI is used only for ARM management-plane storage configuration so private backend bootstrap never needs to expose storage to the public internet for container creation.
Root lockfiles record Windows and Linux checksums. Do not run init -upgrade casually. Reusable contracts require no provider.

## Validation
Run pwsh -File scripts/deployment/validate-terraform.ps1 from the repository root. It checks the branch, formatting, backend-disabled initialization, validation and mocked tests. It never executes live plan/apply/destroy or deploys workloads.
Example files end in .example and are not auto-loaded. Copy only nonsecret input values into ignored local files when a later authorized operation needs them. Bootstrap example IDs intentionally remain empty so they cannot be mistaken for approved access.

## Execution prerequisites
See [state bootstrap runbook](../../docs/deployment/bootstrap.md). Phase 1 quota/ownership/certificate questions remain gates. GitHub federation defaults off; no GitHub settings or Azure identities were changed by this implementation.
All implementation stays on codex/001-azure-temporal-deployment. Never create a new branch or merge this work into main.
