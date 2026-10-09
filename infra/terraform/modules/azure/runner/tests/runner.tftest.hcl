mock_provider "azurerm" {}
variables {
  resource_group_name = "rg-nexusflow"
  location            = "centralindia"
  image_version       = "22.04.202609240"
  subnet_id           = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow-stg-ci/subnets/snet-runner"
  ssh_public_key      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgKVqaTWpBTxGFs5Luu4gPJTSMxtgGr12v5L9OmNyAZ"
}
run "disabled_costs_nothing" {
  command = plan
  assert {
    condition     = length(azurerm_linux_virtual_machine.runner) == 0 && length(azurerm_public_ip.outbound) == 0 && output.reference == null
    error_message = "An idle runner must create no compute or public IP."
  }
}
run "enabled_blocks_inbound" {
  command = plan
  variables { enabled = true }
  assert {
    condition     = length(azurerm_linux_virtual_machine.runner) == 1 && azurerm_linux_virtual_machine.runner[0].disable_password_authentication && length([for rule in azurerm_network_security_group.runner[0].security_rule : rule if rule.name == "DenyAllInbound" && rule.access == "Deny" && rule.direction == "Inbound" && rule.priority == 100 && rule.protocol == "*" && rule.destination_port_range == "*" && rule.destination_address_prefix == "*"]) == 1
    error_message = "Runner must deny every inbound port and use managed identity with password login disabled."
  }
  assert {
    condition     = azurerm_linux_virtual_machine.runner[0].identity[0].type == "SystemAssigned" && azurerm_public_ip.outbound[0].sku == "Standard"
    error_message = "State authentication must use managed identity; outbound must be explicit."
  }
  assert {
    condition     = length(azurerm_network_security_group.runner[0].security_rule) == 5 && toset([for rule in azurerm_network_security_group.runner[0].security_rule : "${rule.protocol}:${rule.destination_port_range}" if rule.direction == "Outbound" && rule.access == "Allow" && rule.destination_address_prefix == "Internet" && rule.priority < 200]) == toset(["Tcp:443", "Tcp:80", "Udp:123"]) && length([for rule in azurerm_network_security_group.runner[0].security_rule : rule if rule.name == "DenyInternet" && rule.direction == "Outbound" && rule.access == "Deny" && rule.priority == 200 && rule.protocol == "*" && rule.destination_port_range == "*" && rule.destination_address_prefix == "Internet"]) == 1
    error_message = "Runner Internet egress must allow only HTTPS, HTTP and NTP before denying other protocols; VNet traffic must retain default access."
  }
}
run "missing_key_rejected" {
  command = plan
  variables {
    enabled        = true
    ssh_public_key = ""
  }
  expect_failures = [var.ssh_public_key]
}
