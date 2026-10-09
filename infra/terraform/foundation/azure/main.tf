module "configuration" {
  source      = "../../modules/contracts"
  environment = var.environment
}
module "resource_group" {
  source   = "../../modules/azure/resource-group"
  mode     = var.resource_group_mode
  location = var.location
  tags     = local.tags
}
locals {
  tags = { project = "nexusflow", environment = "stg", managed_by = "terraform" }
  subnets = {
    nodes             = module.configuration.configuration.network.nodes
    postgres          = module.configuration.configuration.network.postgres
    runner            = module.configuration.configuration.network.runner
    private_endpoints = module.configuration.configuration.network.private_endpoints
  }
}
resource "azurerm_virtual_network" "foundation" {
  name                = "vnet-nexusflow-stg-ci"
  location            = var.location
  resource_group_name = module.resource_group.reference.name
  address_space       = [module.configuration.configuration.network.vnet]
  tags                = local.tags
  lifecycle { prevent_destroy = true }
}
resource "azurerm_subnet" "foundation" {
  for_each                          = local.subnets
  name                              = "snet-${replace(each.key, "_", "-")}"
  resource_group_name               = module.resource_group.reference.name
  virtual_network_name              = azurerm_virtual_network.foundation.name
  address_prefixes                  = [each.value]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = each.key == "private_endpoints" ? "Enabled" : "Disabled"
  dynamic "delegation" {
    for_each = each.key == "postgres" ? [1] : []
    content {
      name = "postgres"
      service_delegation {
        name    = "Microsoft.DBforPostgreSQL/flexibleServers"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
}
resource "azurerm_network_security_group" "runner" {
  name                = "nsg-nexusflow-stg-runner"
  location            = var.location
  resource_group_name = module.resource_group.reference.name
  tags                = local.tags
  security_rule {
    name                       = "DenyInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_subnet_network_security_group_association" "runner" {
  subnet_id                 = azurerm_subnet.foundation["runner"].id
  network_security_group_id = azurerm_network_security_group.runner.id
}
output "private_network" {
  value = {
    vnet_id   = azurerm_virtual_network.foundation.id
    subnet_id = azurerm_subnet.foundation["private_endpoints"].id
  }
}
output "subnet_ids" {
  value = { for name, subnet in azurerm_subnet.foundation : name => subnet.id }
}