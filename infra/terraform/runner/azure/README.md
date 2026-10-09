# Private runner bootstrap root

This root has no active backend initially. Keep local state restricted and encrypted until the runner enables private backend migration. See [the runner runbook](../../../../docs/deployment/runner.md). Use a distinct infrastructure-container key `nexusflow/stg/runner.tfstate`; never reuse foundation or environment state keys.

Copy `staging.tfvars.example` to ignored `staging.tfvars`, keep `enabled=false` until input validation, supply a public SSH key, and resolve an exact Canonical image version. Review the plan before applying. The existing foundation owns the subnet and its NSG; this root owns a second inbound-denying NIC NSG. Its public IP provides explicit outbound routing only.