terraform {
  required_version = ">= 1.10.5, < 1.11.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "= 4.50.0" }
  }
}
variable "enabled" {
  type    = bool
  default = false
}
variable "name" {
  type    = string
  default = "vm-nexusflow-stg-ci-runner"
}
variable "resource_group_name" {
  type = string
  validation {
    condition     = var.resource_group_name == "rg-nexusflow"
    error_message = "Runner must remain in rg-nexusflow."
  }
}
variable "location" { type = string }
variable "subnet_id" { type = string }
variable "ssh_public_key" {
  type    = string
  default = ""
  validation {
    condition     = !var.enabled || can(regex("^ssh-(rsa|ed25519) [A-Za-z0-9+/=]+", var.ssh_public_key))
    error_message = "An enabled runner needs an SSH public key; inbound SSH remains blocked."
  }
}
variable "vm_size" {
  type    = string
  default = "Standard_B1ms"
  validation {
    condition     = contains(["Standard_B1ms", "Standard_B2s", "Standard_D2s_v5"], var.vm_size)
    error_message = "Choose a reviewed small staging runner size."
  }
}
variable "image_version" {
  type    = string
  default = "latest"
  validation {
    condition     = !var.enabled || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_version))
    error_message = "Resolve an exact Ubuntu image version before enabling the runner."
  }
}
variable "tags" {
  type    = map(string)
  default = {}
}
resource "azurerm_public_ip" "outbound" {
  count               = var.enabled ? 1 : 0
  name                = "pip-${var.name}-outbound"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}
resource "azurerm_network_security_group" "runner" {
  count               = var.enabled ? 1 : 0
  name                = "nsg-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  dynamic "security_rule" {
    for_each = {
      AllowInternetHttps = { priority = 110, protocol = "Tcp", port = "443" }
      AllowInternetHttp  = { priority = 120, protocol = "Tcp", port = "80" }
      AllowInternetNtp   = { priority = 130, protocol = "Udp", port = "123" }
    }
    content {
      name                       = security_rule.key
      priority                   = security_rule.value.priority
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = security_rule.value.protocol
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
    }
  }
  security_rule {
    name                       = "DenyInternet"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}
resource "azurerm_network_interface" "runner" {
  count               = var.enabled ? 1 : 0
  name                = "nic-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.outbound[0].id
  }
}
resource "azurerm_network_interface_security_group_association" "runner" {
  count                     = var.enabled ? 1 : 0
  network_interface_id      = azurerm_network_interface.runner[0].id
  network_security_group_id = azurerm_network_security_group.runner[0].id
}
resource "azurerm_linux_virtual_machine" "runner" {
  count                           = var.enabled ? 1 : 0
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.vm_size
  admin_username                  = "runneradmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.runner[0].id]
  tags                            = var.tags
  identity { type = "SystemAssigned" }
  admin_ssh_key {
    username   = "runneradmin"
    public_key = var.ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = var.image_version
  }
  depends_on = [azurerm_network_interface_security_group_association.runner]
}
output "reference" {
  value = var.enabled ? {
    vm_id        = azurerm_linux_virtual_machine.runner[0].id
    vm_name      = var.name
    principal_id = azurerm_linux_virtual_machine.runner[0].identity[0].principal_id
    private_ip   = azurerm_network_interface.runner[0].private_ip_address
    public_ip    = azurerm_public_ip.outbound[0].ip_address
  } : null
}
