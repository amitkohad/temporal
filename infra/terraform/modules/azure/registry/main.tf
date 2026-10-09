variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "sku" {
  type    = string
  default = "Basic"
  validation {
    condition     = contains(["Basic", "Premium"], var.sku)
    error_message = "Only Basic staging or Premium private registries are supported."
  }
}
variable "private_access" {
  type    = bool
  default = false
}
variable "private_endpoint_subnet_id" {
  type    = string
  default = null
}
variable "virtual_network_id" {
  type    = string
  default = null
}
variable "writer_object_ids" {
  type    = set(string)
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
resource "azurerm_container_registry" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.sku
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = !var.private_access
  network_rule_bypass_option    = "None"
  tags                          = var.tags
  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = !var.private_access || (var.sku == "Premium" && var.private_endpoint_subnet_id != null && var.virtual_network_id != null)
      error_message = "Private registries require Premium, a private endpoint subnet, and a VNet."
    }
  }
}
resource "azurerm_private_dns_zone" "this" {
  count               = var.private_access && var.private_endpoint_subnet_id != null && var.virtual_network_id != null ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  count                 = var.private_access && var.private_endpoint_subnet_id != null && var.virtual_network_id != null ? 1 : 0
  name                  = "${var.name}-vnet"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[0].name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}
resource "azurerm_private_endpoint" "this" {
  count               = var.private_access && var.private_endpoint_subnet_id != null && var.virtual_network_id != null ? 1 : 0
  name                = "pe-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags
  private_service_connection {
    name                           = "${var.name}-registry"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "registry"
    private_dns_zone_ids = [azurerm_private_dns_zone.this[0].id]
  }
}
resource "azurerm_role_assignment" "writer" {
  for_each             = var.writer_object_ids
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = each.value
}
output "reference" {
  value = {
    id             = azurerm_container_registry.this.id
    name           = azurerm_container_registry.this.name
    login_server   = azurerm_container_registry.this.login_server
    private_access = var.private_access
  }
}