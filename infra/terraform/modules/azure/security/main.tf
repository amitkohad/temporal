variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name" { type = string }
variable "tenant_id" { type = string }
variable "private_endpoint_subnet_id" { type = string }
variable "virtual_network_id" { type = string }
variable "secret_reader_object_ids" {
  type    = set(string)
  default = []
}
variable "secret_operator_object_ids" {
  type    = set(string)
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
resource "azurerm_key_vault" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  network_acls {
    bypass         = "None"
    default_action = "Deny"
  }
  tags = var.tags
  lifecycle { prevent_destroy = true }
}
resource "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  name                  = "${var.name}-vnet"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.vault.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}
resource "azurerm_private_endpoint" "vault" {
  name                = "pe-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  private_service_connection {
    name                           = "vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "vault"
    private_dns_zone_ids = [azurerm_private_dns_zone.vault.id]
  }
  tags = var.tags
}
resource "azurerm_role_assignment" "reader" {
  for_each             = var.secret_reader_object_ids
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}
resource "azurerm_role_assignment" "operator" {
  for_each             = var.secret_operator_object_ids
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}
output "reference" {
  value = { id = azurerm_key_vault.this.id, uri = azurerm_key_vault.this.vault_uri, name = azurerm_key_vault.this.name }
}