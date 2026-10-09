# Attended private runner

The separate `infra/terraform/runner/azure` root creates an on-demand Ubuntu 22.04 runner in the existing runner subnet. It starts with local protected state because its purpose is to reach the private state service for the first migration. Its eventual backend is the infrastructure container with the distinct key `nexusflow/stg/runner.tfstate`. Never move these resources into the environment root without an explicit Terraform state move.

`enabled=false` creates no VM, disk, NIC, public IP, or role grants. For bootstrap checks, use `Standard_B1ms`; its 1 GiB memory is not a Temporal build sizing recommendation. Review larger build sizing before compiling. Resolve a concrete Canonical image version before enabling. OS images and the GitHub runner agent are infrastructure tooling; Temporal application binaries still must be built from the pinned fork commit.

The VM uses a Standard public IP solely to establish explicit outbound connectivity. Both its NIC NSG and the foundation runner subnet NSG deny every inbound packet. The NIC NSG permits Internet-bound TCP 443/80 and UDP 123 at priorities 110/120/130, then denies other Internet-bound traffic at priority 200. Default VNet outbound access remains available for private state, PostgreSQL, Vault, and AKS endpoints. Azure platform DNS, IMDS, and VM-agent traffic retain their default platform handling; this module does not deny AzurePlatformDNS, AzurePlatformIMDS, or AzurePlatformLKM. No SSH port, Bastion, VPN, NAT gateway, or inbound application service is created. Azure VM Run Command reaches the agent through Azure's management plane. The system-assigned managed identity receives only Storage Blob Data Contributor on explicitly supplied backend containers. It has no subscription Contributor, Owner, or role administration privilege. Resource changes performed remotely require separate reviewed permissions.

For bootstrap migration, an attended operator can temporarily supply bootstrap, infrastructure, and platform container IDs. After migration, remove unneeded entries and apply that narrower access map. This attended identity is not a GitHub workload identity and does not inherit its future permissions.

## Private state verification

After the VM and role grants exist, run from the authoritative deployment branch:

```powershell
./scripts/deployment/runner-check-state.ps1 -StorageAccountName stnexusflowtf7c5841
```

The script fixes the subscription and resource group, validates input literals, and submits only a nonsecret Python probe through Run Command. The probe resolves the Blob hostname exclusively to private IPs, obtains a storage token from IMDS, and lists each requested container without returning blob names or token values. In each container it creates a unique empty probe blob, obtains a 15-second lease, verifies a competing lease is rejected with HTTP 409, and releases and deletes only its own probe in a finally block. Backend soft-delete/version retention may retain a deleted empty probe temporarily. It reports access and lease success markers for every container. DNS propagation and role assignment propagation can delay success; rerun only after investigating the actual failure. Optional `-PrivateHosts` accepts only the reviewed PostgreSQL/Vault names or a private Central India AKS hostname. It checks private DNS and TCP 5432/443; this is connectivity evidence and does not verify database login, Kubernetes RBAC, or Key Vault authorization. The probe does not migrate Terraform state. Preserve restricted local state and its encrypted backup until remote lineage, serial, and clean plans have been checked.

## Ephemeral GitHub jobs

`scripts/deployment/runner-jit.sh` consumes `encoded_jit_config` from stdin and runs one job from an installed, digest-verified official GitHub runner package copied into a private temporary directory. It cleans that directory on exit. A later delivery workflow must request JIT configuration with a short-lived GitHub App token, supply it without shell tracing, verify the runner package digest, and restrict the protected staging environment to the authoritative branch. No registration token, JIT config, GitHub private key, or runner credentials belong in Terraform, cloud-init, source control, or permanent files. Treat callers with Run Command permission as VM administrators.

JIT configuration is passed through the GitHub agent's supported command argument; it is visible to local privileged process inspection while active. Run one isolated job on the VM, never untrusted pull requests alongside privileged infrastructure jobs. The shell helper alone does not establish GitHub environment protections or Azure federation. It has not been connected to a live GitHub workflow.

## Egress limits

NSG rules filter destination ranges, ports, and protocols. They do not restrict HTTPS to GitHub, Azure, or approved package registries, and do not prevent exfiltration over allowed web ports. HTTP remains enabled for signed OS package repositories; TLS and artifact digest verification remain the caller's responsibility. Private VNet access is broad under the default VirtualNetwork rule and must not be described as a per-service allowlist. These rules cover the attended runner only; AKS outbound requirements require their own verified design. No paid firewall or FQDN proxy is introduced.

## Cost and cleanup

Deallocate after attended work to stop VM compute charges. Managed disk and static public IP charges continue while deallocated. For longer idle periods, review a runner-root plan with `enabled=false` and apply it to remove only the runner, its explicit outbound IP, disk, NIC, NSG, and grants. Keep state files and never target-delete the shared VNet or backend. No automatic shutdown schedule is configured by this module.

Sources: [Azure Run Command](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command), [VM managed identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/how-to-configure-managed-identities?pivots=qs-configure-cli-windows-vm), [GitHub ephemeral runners](https://docs.github.com/en/actions/reference/runners/self-hosted-runners#ephemeral-runners-for-autoscaling).
NSG platform behavior: [Azure NSG overview](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview), [Azure platform virtual IP](https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16).
