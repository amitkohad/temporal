# Private access and identity decisions

Date: 2026-10-09. This is a selected access design, not a configured connection.

## Access topology
Private AKS API, private Temporal frontend and PostgreSQL delegated-subnet VNet integration remain required.
Basic ACR uses a public HTTPS endpoint with Entra authentication and disabled admin credentials, explicitly approved by the user for staging cost. No anonymous image access or embedded registry password is permitted. Azure nodes reach the registry through the controlled outbound path.
Build-only work can use eligible GitHub-hosted public-repository runners. Private API/database/schema/rollout operations use an ephemeral VNet-connected VM runner independent of Temporal readiness. Provision it later through authorized management-plane Terraform. Register it with short-lived credentials; remove it after work.
Do not add a permanent VPN, Bastion, NAT Gateway or always-on runner just for staging. Operator connectivity initially uses the attended private runner and supported management-plane remote-command facilities. Prove RBAC/DNS access before using them; add VPN only if actual operator needs justify it.

## DNS and endpoints
Use Azure Private DNS for AKS and PostgreSQL and link the staging VNet. Use cluster DNS for internal Temporal services. Source-built smoke workers run inside the VNet/cluster; frontend initially needs no separately billed load balancer.
Keep workload-identity and cloud endpoint annotations in Azure overrides. Never open frontend or PostgreSQL to the internet as an automatic connectivity workaround.

## Federation and least privilege
Trust only repository amitkohad/temporal, the designated protected staging environment and the authoritative branch codex/001-azure-temporal-deployment. Never trust fork PR identities with cloud write permissions. No workflow uses main as an implementation destination.
Bootstrap credentials are the human Azure operator's existing login. The future operator must be permitted to manage scoped resources/role assignments and approved Entra federation. No such elevated permission has been verified.
Use separate infrastructure, registry-writer, deployment and database-migration responsibilities. Node registry access uses AcrPull for selected classic registry RBAC; if registry mode changes, update roles to the supported ABAC reader/writer equivalents.
Protect state and secret stores, and never export admin kubeconfig or migration credentials to server pods.

## TLS and authorization
Use certificate validation on PostgreSQL and internode/client TLS for Temporal. Select certificate issuer/trust and approved client claims before runtime implementation. Network isolation alone does not authorize API requests.

## Outstanding ownership
Named bootstrap/federation approver, operator client identity, certificate authority and private-access test evidence remain pre-implementation/execution gates. This document chooses the topology; it does not claim identity resources, DNS or runners exist.

Sources: [Private AKS](https://learn.microsoft.com/en-us/azure/aks/private-clusters), [Private cluster access](https://learn.microsoft.com/en-us/azure/aks/access-private-cluster), [PostgreSQL private networking](https://learn.microsoft.com/en-us/azure/postgresql/network/concepts-networking-private), [ACR registry roles](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-abac-repository-permissions).
