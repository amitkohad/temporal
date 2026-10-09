# Staging capacity and cost decisions

Date: 2026-10-09. Goal: minimum practical cost for an intermittent staging pilot. No spending cap, as explicitly requested. Cost monitoring is informational; do not stop workloads merely because an invented monetary threshold is exceeded.

## Selected pilot profile
| Component | Selection | Limit |
|---|---|---|
| AKS control plane | Free tier | No financially backed control-plane SLA |
| AKS compute | One shared system pool, Standard_D2s_v5, initial/min/max=1 | 2 vCPU, 8 GiB; no dedicated second pool, no HA |
| Temporal roles | Frontend/history/matching/internal worker, one replica each | Low-load experiment; resource fit must be proven |
| PostgreSQL | Flexible Server, PostgreSQL 17 candidate, Burstable Standard_B1ms, 32 GiB storage | No HA; low-throughput pilot, monitor CPU credits and memory |
| PostgreSQL upgrade option | Standard_B2s only if measurements justify it | Higher cost requires an explicit profile change |
| ACR | Basic, authenticated public HTTPS endpoint | User approved; admin account disabled; no Private Link |
| Frontend | Private ClusterIP initially | In-cluster runner/test clients; add internal LB only when justified |
| Egress | Standard LB outbound path | Avoid dedicated NAT Gateway/Azure Firewall for pilot; validate allowed endpoints |
| State/secrets | Small protected storage and Key Vault | Retain required security; include endpoint/transaction costs |
| Telemetry | Existing platform metrics plus minimal self-managed collection/logs | No always-on paid managed monitoring bundle by default |
| Runner | Ephemeral VM only for private deployment/test operations | Public hosted build-only CI where permitted; no always-on runner |

Single shared node and no database HA are deliberate staging exceptions to the production topology. A system pool may host application pods for the pilot; do not apply a system-only taint that would make Temporal unschedulable. Keep separate role Deployments. Production needs separate node pools, redundancy and measured capacity.

## Observed regional offerings and quota
Standard_D2s_v5 and Standard_D2s_v3 returned no restrictions and zones 1, 2 and 3. DSv5 family quota: 0/20 vCPUs consumed; regional cores: 4/20 consumed. One pilot node uses 2 additional vCPUs; reserve capacity for upgrade surge and ephemeral runners, never assume the full remaining 16 cores belong to this feature.
PostgreSQL catalog includes 17/18 and B1ms/B2s offerings; this does not prove subscription database quota or live provisioning capacity.
AKS regional default minor is 1.35, returned by the installed aks-preview extension. Select a supported exact patch during implementation; do not hardcode an unverified patch.
ContainerService, ContainerRegistry, DBforPostgreSQL, Network, Storage, KeyVault, ManagedIdentity, OperationalInsights and Compute providers are Registered. Authorization and any additional selected provider registrations still require preflight.

HA capability response is inconsistent: zoneRedundantHaSupported=Disabled, zoneRedundantHaAndGeoBackupSupported=Enabled. SKU payload also includes broad supportedHaMode values. These fields do not establish a supported production HA deployment. Pilot HA is disabled. Resolve production HA against chosen SKU, API and regional documentation before selecting production capacity.

## Pilot test envelope (proposed defaults)
- Baseline: 1 workflow start/second, at most 100 concurrently open workflows, short histories (up to 100 events) and small payloads.
- Burst test: 5 starts/second for five minutes; reduce or scale only from measurements.
- Visibility: 1 list/filter query per second with pagination; validate expected custom search attributes.
- Retention: three days for completed workflows; avoid storing real production or sensitive test data.
- Service latency target: frontend non-long-poll API p95 below 500 ms at baseline, measured on a low-latency private client.
- Durability: accepted starts remain discoverable; test workflows resume after role restart. No production SLA is claimed.
- Initial history shard proposal: 128, to be validated before cluster initialization; once initialized do not change in place.
- Connection pool budget and per-role requests/limits are implementation/load-test decisions. Do not infer sustainable throughput from these proposed targets.

## Public retail cost evidence
Public Azure Retail Prices API queried for Central India Consumption rates, USD, on 2026-10-09. Selected regular Linux VM meters, not Spot/Low Priority:
- Standard_D2s_v5: USD 0.101/hour.
- PostgreSQL Flexible Server B1MS: USD 0.0245/hour.
- PostgreSQL storage: USD 0.131/GB-month.
- Basic Registry Unit: USD 0.1666/day (regional response reports a non-primary shared registry meter).

Using 730 compute hours and 30 registry days:
| Component | Always running | 176 compute hours (8 hours x 22 days) |
|---|---:|---:|
| One AKS VM | USD 73.73 | USD 17.78 |
| B1ms PostgreSQL compute | USD 17.89 | USD 4.31 |
| 32 GB database storage | USD 4.19 | USD 4.19 |
| Basic ACR | USD 5.00 | USD 5.00 |
| Core subtotal | USD 100.81 | USD 31.28 |

This is a subtotal, not an all-in quote: node OS disks, load balancer/outbound IP, private endpoints/DNS, state storage, vault operations, excess registry storage, backup excess, logs, bandwidth and ephemeral runner compute/disks are additional. Taxes, exchange rates, account discounts and credits are not included. Never budget the unrelated HorizonDB free-storage meters as Flexible Server storage.

## Free resources and shutdown policy
Use the AKS Free control-plane tier and eligible public-repository GitHub-hosted build minutes. Terraform and self-managed observability software have no licensing charge; their infrastructure still costs money.
The account name suggests a Visual Studio benefit, but credit entitlement, remaining balance and spending-limit policy were not established (account metadata returned null). Eligible Enterprise benefits can include USD 150/month; do not count on it or assume an Azure free-account PostgreSQL offer applies.
Run the pilot only during testing when practical. AKS stop/start and PostgreSQL stop/start are future authorized operations; stopping compute does not stop storage/registry/network charges. PostgreSQL may automatically restart after its supported stop duration. No shutdown automation was created.
Avoid Spot for the only node. Prefer pausing the environment and reducing retained logs/images over compromising workflow data or runtime security.

## Execution blockers
Verify PostgreSQL subscription quota/live capacity, exact supported versions, all-in price estimate/credit entitlement and role-assignment permissions before provisioning. No monetary cap is required by the user. Any optional HA, second pool, NAT, Premium ACR, managed telemetry or VPN purchase must be justified explicitly.

Sources: [AKS pricing](https://azure.microsoft.com/en-us/pricing/details/kubernetes-service/), [ACR pricing](https://azure.microsoft.com/en-us/pricing/details/container-registry/), [PostgreSQL pricing](https://azure.microsoft.com/en-us/pricing/details/postgresql/flexible-server/), [Azure retail prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices), [Visual Studio credits](https://learn.microsoft.com/en-us/visualstudio/subscriptions/vs-azure-eligibility), [Visual Studio Azure FAQ](https://learn.microsoft.com/en-us/visualstudio/subscriptions/faq/subscriber/azure/), [AKS stop/start](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster).
