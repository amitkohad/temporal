# Azure private network foundation

This root owns the VNet, four subnets, runner inbound isolation, and subnet association. It references the existing `rg-nexusflow` resource group. The infrastructure root must consume these subnet IDs rather than recreate them.

Start with local state because the private backend depends on this network. Local `.tfstate`, `.tfvars`, and saved plans are ignored by Git. Migrate this root into the infrastructure container using the separate key `nexusflow/stg/foundation.tfstate` after the private operator path is verified. Never reuse the infrastructure root key.

All subnets explicitly disable default outbound access. AKS will use its Standard Load Balancer outbound rules; an on-demand runner requires an explicit outbound method. No NAT Gateway, VPN gateway, Bastion, public IP, or compute is created by this root.

Use `staging.tfvars.example` as the input template. Run `terraform init`, `terraform validate`, `terraform test`, and `terraform plan -var-file=staging.tfvars -out=foundation.tfplan`; review the saved plan before applying it. Keep all work on `codex/001-azure-temporal-deployment`.