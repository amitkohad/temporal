# Private network and dependency connectivity

The foundation Terraform root owns the VNet, all four subnets, and the runner subnet NSG. The environment root owns the AKS node subnet NSG and its subnet association; the runner root owns the runner NIC NSG and its NIC association. These are separate resources with separate state owners. Addressing is `10.42.0.0/16`: AKS nodes `10.42.0.0/23`, PostgreSQL delegated subnet `10.42.2.0/27`, runner `10.42.3.0/27`, and private endpoints `10.42.4.0/27`. Kubernetes services use `10.43.0.0/16` with DNS `10.43.0.10`; overlay pods use `10.44.0.0/16`. Validate overlap against all connected networks before peering. Overlay addresses are not directly exposed to clients outside the cluster.

## DNS and operator path

Use Azure-provided DNS in this VNet. AKS creates its `privatelink.centralindia.azmk8s.io` system zone in the managed node resource group and links the existing VNet. Its control-plane identity has Network Contributor on this VNet to establish that link. The Terraform operator needs role-assignment authority. Do not assign the control-plane identity Owner over the application resource group.

State storage uses `privatelink.blob.core.windows.net`, Key Vault uses `privatelink.vaultcore.azure.net`, and private Premium ACR uses `privatelink.azurecr.io`. PostgreSQL uses the delegated-subnet integration zone supplied by its module, ending in `postgres.database.azure.com`. Each zone must have one Terraform owner and its own VNet link. Basic ACR resolves publicly. Verify actual FQDN resolution rather than assuming that the public service suffix implies public resource access.

A runner in this VNet can reach the private API, PostgreSQL and private endpoints. Local workstations and hosted GitHub runners cannot connect without an explicit private route and DNS path. A peered VNet also needs the relevant zone links or conditional forwarding. Avoid exposing the API, database, state or vault to bypass that requirement. Runner inbound traffic is denied; management-plane Run Command supports bootstrap checks. It requires a healthy guest agent and explicit outbound connectivity, which the runner composition must supply.

## Allowed dependency flows

These are requirements for later Kubernetes NetworkPolicies and any future network firewall. This phase does not yet install workload policies. Ports come from `config/docker.yaml`; change the matrix when deployed configuration changes.

| Source | Destination | Protocol / port | Purpose |
|---|---|---|---|
| Approved SDK workers, UI backend, operator | Temporal frontend private service | TCP 7233 | Authenticated gRPC requests |
| Temporal service roles | Frontend, history, matching, worker pods | TCP 7233, 7234, 7235, 7239 | Internal service RPC |
| Temporal service roles | Service membership peers | TCP 6933, 6934, 6935, 6939 | Ring membership and failure detection |
| Temporal services and migration job | PostgreSQL private FQDN | TCP 5432 | TLS persistence and visibility; separate database credentials |
| Pods | Cluster DNS | UDP and TCP 53 | Service and dependency resolution |
| Nodes and runner | Azure DNS | UDP and TCP 53 | Private zone resolution |
| Runner | Private AKS API | TCP 443 | Entra-authenticated deployment and verification |
| Runner | State Blob and Key Vault private endpoints | TCP 443 | Terraform state and managed-identity secrets access |
| Nodes and build runner | ACR login and regional data endpoints | TCP 443 | Authenticated image pull or push |
| Scraper | Temporal metrics endpoint | Configured metrics TCP port | Enable only when the observability configuration supplies a listener |

Optional frontend HTTP 7243, internal frontend 7236/7246 and membership 6936 are closed unless the deployment explicitly enables those listeners. Profiling must remain disabled or restricted to operator access. Application workers may require business-service outbound access; add named dependencies when deploying those workers, not a blanket Temporal policy allowance.

## Current staging egress and cost

Foundation subnets disable implicit default outbound access. AKS explicitly uses a Standard load balancer with one managed outbound public IP for node SNAT. Its private API and private Temporal services remain private; an outbound public IP does not create a Temporal ingress listener. Load-balancer rules, IP and node disks incur charges even with the Free AKS control-plane tier. Runner connectivity is independently configured; an AKS outbound IP does not provide egress for a VM in another subnet.

There is no Azure Firewall, NAT Gateway, proxy or domain allowlist in this staging foundation. The environment root's node subnet NSG allows Internet-bound TCP 443/80 and UDP 123 at priorities 110/120/130, then denies other Internet-bound protocols at priority 200. The runner NIC NSG uses the same protocol boundary independently; its update must be applied and verified before claiming that runner restriction is live. The load balancer supplies SNAT, not destination filtering. Cilium enables Kubernetes policy enforcement but does not restrict anything until policies are installed. Private endpoints restrict the endpoint path, not arbitrary node egress. Runner subnet and NIC NSGs deny inbound connections. The NSG rules retain default VirtualNetwork outbound access and Azure platform DNS/IMDS/agent behavior. They do not filter FQDNs or prevent transfers to arbitrary destinations on allowed web ports. Azure default outbound NSG allowances alone do not establish an internet route.

When validating or tightening the protocol restrictions, account for AKS control-plane and node management dependencies, Azure identity endpoints, Microsoft artifact registries and package mirrors, OS updates and time synchronization. Exact AKS requirements vary by region, networking mode and enabled addons; consult the current [Microsoft outbound requirements](https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress). Private clusters omit some public tunnel requirements, so do not blindly allow public API UDP 1194/TCP 9000. Build runners additionally need the approved source repository, Go module sources and pinned OS/base-image registries.

Production must decide whether to use UDR plus Azure Firewall/NVA/proxy or a supported network-isolated AKS design. An NSG cannot filter FQDNs, and switching to NAT Gateway provides SNAT capacity rather than an allowlist. Account for recurring charges and API/network replacement risks before changing the deployed outbound mode. Verify node startup, registry pulls, managed identity, DNS, PostgreSQL, state and vault access after any restriction.

## Attended operator permissions

The runner retains Reader on `rg-nexusflow` and container-scoped state permissions for verification. A one-time runner NSG update may use Network Contributor scoped only to `nsg-vm-nexusflow-stg-ci-runner`. Remove that temporary assignment immediately after the saved plan is applied and verified, including failure cleanup. Do not broaden it to the VNet, runner subnet NSG, or entire resource group. The independent foundation-owned subnet NSG continues denying inbound traffic while the NIC NSG is updated. Run Command is an administrative path; scope permission to the attended operator and do not expose it to untrusted workflows.

## Verification

From the private runner, resolve the emitted private API, PostgreSQL, state and vault FQDNs and verify private answers within the expected subnets. Check TCP 443/5432 reachability without printing tokens or secrets. Verify Entra API authorization, state blob access and authenticated registry pulls independently; an open TCP socket proves connectivity, not authorization. Once workloads exist, test permitted RPC/membership/DB flows and denied cross-namespace access. Record observed results separately from this required-flow design.

References: [Private AKS and DNS](https://learn.microsoft.com/en-us/azure/aks/private-clusters), [Private cluster access](https://learn.microsoft.com/en-us/azure/aks/private-cluster-connect), [AKS outbound dependencies](https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress).