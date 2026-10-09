# Platform and release contracts

These are interface designs, not implemented modules or live endpoints.

## Environment input contract
Required: environment name/classification, subscription/tenant/location, resource_group_name=rg-nexusflow, resource_group_mode=existing|create, naming prefix, approved source commit, nonoverlapping CIDRs, Kubernetes/PostgreSQL versions, sizing profile, runner access topology, TLS trust/client authorization, recovery and monitoring owners.
Optional with reviewed defaults: retention, node autoscale bounds, tags, database storage/backup window, alert thresholds.
Reject unsupported versions, empty production objectives, public data endpoints, globally invalid names, secret literals, overlapping CIDRs and duplicate state keys.

## Azure adapter output contract
| Output | Shared-layer meaning | Sensitivity |
|---|---|---|
| cluster_reference | Context/reference for separately initialized Kubernetes provider | Nonsecret; never export admin kubeconfig |
| registry_endpoint | OCI registry host | Nonsecret |
| postgres_endpoint / port | TLS-verified database DNS name and port | Nonsecret |
| databases | persistence and visibility names | Nonsecret |
| secret_references | Logical runtime/migration secret names | References only; no password values |
| trust_references | Logical TLS trust/certificate references | References only |
| identity_bindings | Adapter-managed service-account bindings | Azure IDs stay in adapter overrides |
| connectivity | Runner/operator DNS/routes and private access prerequisites | Nonsecret |
| observability | Metrics/log destinations and owner | Nonsecret |

Shared layer consumes stable logical values, not Azure resource types. No direct remote-state exposure of credentials; narrowly scoped output handoff is preferred.

## Release manifest contract
Required: source URL, full immutable commit, server-reported version, Go/build-tool versions, build flags, OS/architecture, server and SQL-tool OCI digests, base provenance, schema version pairs and schema content checksums, SBOM/provenance locations, scan policy results, chart version, values hash, timestamp and release identity.
At inspected baseline: PostgreSQL persistence=1.19 and visibility=1.14; derive from the selected commit instead of hardcoding those values forever.
Validate digest syntax, source consistency and schema compatibility. Reject branch-only revisions and latest references.

## Schema operation contract
Inputs: release manifest, database name/type, initialize|upgrade|verify operation, schema-owner secret reference, verified TLS endpoint, expected current/target versions.
Rules: exclusive migration lease; never drop; initialize only an empty/uninitialized database; upgrade monotonically using matching versioned schemas; reject newer/unexpected versions; bounded retries, clear exit status, sanitized logs and audit record. Partial migrations must be assessed against repository tool semantics before retry.
Runtime role has required DML permissions, not schema ownership. Migration credentials are unavailable to long-running server pods.

## Kubernetes contract
Four separately configured services; shared image digest with role selection verified against the selected server; pod-address advertisement; service/membership network policy; graceful drain; TLS-aware probes; resources, topology, disruption budgets, autoscale bounds, namespace/retention limits. Cloud load-balancer and workload-identity annotations live only in azure.values.yaml.
No Web UI or production application worker image is supplied by the server source. Monitoring agents, base images and managed services require an explicit source-only scope decision.
