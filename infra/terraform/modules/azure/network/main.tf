terraform {
  required_version = ">= 1.10.5, < 1.11.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "= 4.50.0" }
  }
}
variable "name" {
  type    = string
  default = "nsg-nexusflow-stg-nodes"
}
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "nodes_subnet_id" { type = string }
variable "tags" { type = map(string) }
resource "azurerm_network_security_group" "nodes" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  dynamic "security_rule" {
    for_each = {
      InternetHttps = { priority = 110, protocol = "Tcp", port = "443", access = "Allow" }
      InternetHttp  = { priority = 120, protocol = "Tcp", port = "80", access = "Allow" }
      InternetNtp   = { priority = 130, protocol = "Udp", port = "123", access = "Allow" }
      DenyInternet  = { priority = 200, protocol = "*", port = "*", access = "Deny" }
    }
    content {
      name                       = security_rule.key
      priority                   = security_rule.value.priority
      direction                  = "Outbound"
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
    }
  }
}
resource "azurerm_subnet_network_security_group_association" "nodes" {
  subnet_id                 = var.nodes_subnet_id
  network_security_group_id = azurerm_network_security_group.nodes.id
}
