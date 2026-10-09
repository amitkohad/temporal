# PostgreSQL foundation
Creates PostgreSQL 17 B1ms/32 GiB with seven-day backup retention, delegated private networking, Entra-only authentication, and separate protected `temporal` and `temporal_visibility` databases. Azure-managed backups protect persistence; Temporal history retention is a separate runtime setting. Server and databases reject destruction. No credentials are accepted or exported.

Pass an existing delegated subnet and VNet, an Entra administrator, and an optional profile for version, SKU, storage, retention, zones, and HA mode. HA requires a non-burstable SKU; actual region capacity remains an apply-time prerequisite. The server system identity supports Entra integration; directory-read requirements for additional service principals must be assessed before creating runtime identities.

This module does not initialize Temporal schemas or SQL grants. The runtime must obtain renewable Entra database tokens or use a separately reviewed password-authentication configuration and externally generated Key Vault secrets. A fixed Entra token is not a durable Temporal password. Do not deploy Temporal until authentication refresh, separate schema/runtime roles, TLS, and grants are implemented. Private DNS access from a runner is required for data-plane migrations.

Validate with `terraform init -backend=false`, `terraform validate`, and `terraform test`. Tests mock Azure and do not provision resources.
Azure extension allowlisting enables BTREE_GIN because the repository visibility schema creates that extension. The schema phase must create the extension in temporal_visibility using its privileged migration identity.

The DNS zone uses a private- prefix because Azure rejects a zone name equal to the server FQDN. See [Azure private networking DNS requirements](https://learn.microsoft.com/en-us/azure/postgresql/network/concepts-networking-private).

Initial zone and standby-zone inputs guide creation. The lifecycle preserves Azure-assigned zones and subsequent HA failover placement, following [AzureRM PostgreSQL zone guidance](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v4.50.0/website/docs/r/postgresql_flexible_server.html.markdown). Editing those inputs alone does not move an existing server; deliberate zone relocation requires a separately reviewed operational procedure. HA mode, SKU, backup retention, and authentication remain managed.
