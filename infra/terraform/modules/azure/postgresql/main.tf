variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name" { type = string }
variable "tenant_id" { type = string }
variable "delegated_subnet_id" { type = string }
variable "virtual_network_id" { type = string }
variable "administrator" {
  type = object({ object_id = string, principal_name = string, principal_type = optional(string, "User") })
  validation {
    condition     = contains(["User", "Group", "ServicePrincipal"], var.administrator.principal_type)
    error_message = "Administrator type must be User, Group, or ServicePrincipal."
  }
}
variable "profile" {
  type = object({
    version                = optional(string, "17")
    sku_name               = optional(string, "B_Standard_B1ms")
    storage_mb             = optional(number, 32768)
    backup_retention_days  = optional(number, 7)
    high_availability_mode = optional(string)
    zone                   = optional(string)
    standby_zone           = optional(string)
  })
  default = {}
  validation {
    condition     = contains(["16", "17"], var.profile.version) && var.profile.backup_retention_days >= 7 && var.profile.backup_retention_days <= 35
    error_message = "Use PostgreSQL 16 or 17 and backup retention between 7 and 35 days."
  }
  validation {
    condition     = var.profile.high_availability_mode == null ? true : contains(["SameZone", "ZoneRedundant"], var.profile.high_availability_mode) && !startswith(var.profile.sku_name, "B_")
    error_message = "HA requires SameZone or ZoneRedundant and a non-burstable SKU."
  }
}
variable "tags" {
  type    = map(string)
  default = {}
}
resource "azurerm_private_dns_zone" "postgresql" {
  name                = "private-${var.name}.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  name                  = "${var.name}-vnet"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgresql.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}
resource "azurerm_postgresql_flexible_server" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = var.profile.version
  sku_name                      = var.profile.sku_name
  storage_mb                    = var.profile.storage_mb
  backup_retention_days         = var.profile.backup_retention_days
  geo_redundant_backup_enabled  = false
  auto_grow_enabled             = false
  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.postgresql.id
  public_network_access_enabled = false
  zone                          = var.profile.zone
  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = var.tenant_id
  }
  identity { type = "SystemAssigned" }
  dynamic "high_availability" {
    for_each = var.profile.high_availability_mode == null ? [] : [var.profile.high_availability_mode]
    content {
      mode                      = high_availability.value
      standby_availability_zone = var.profile.standby_zone
    }
  }
  tags       = var.tags
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
  lifecycle {
    prevent_destroy = true
    # Azure selects zones at creation and changes them during HA failover.
    ignore_changes = [zone, high_availability[0].standby_availability_zone]
  }
}
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "operator" {
  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  object_id           = var.administrator.object_id
  principal_name      = var.administrator.principal_name
  principal_type      = var.administrator.principal_type
}
resource "azurerm_postgresql_flexible_server_database" "temporal" {
  for_each  = toset(["temporal", "temporal_visibility"])
  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
  lifecycle { prevent_destroy = true }
}
output "reference" {
  value = {
    id                 = azurerm_postgresql_flexible_server.this.id
    fqdn               = azurerm_postgresql_flexible_server.this.fqdn
    database_names     = keys(azurerm_postgresql_flexible_server_database.temporal)
    administrator_name = var.administrator.principal_name
    authentication     = "EntraOnly"
  }
}
resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = "BTREE_GIN"
}