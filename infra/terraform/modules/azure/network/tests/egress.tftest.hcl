mock_provider "azurerm" {}
variables {
  resource_group_name = "rg-nexusflow"
  location            = "centralindia"
  nodes_subnet_id     = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow-stg-ci/subnets/snet-nodes"
  tags                = {}
}
run "reviewed_internet_protocols" {
  command = plan
  assert {
    condition     = alltrue([for rule in azurerm_network_security_group.nodes.security_rule : rule.destination_address_prefix == "Internet"]) && length([for rule in azurerm_network_security_group.nodes.security_rule : rule if rule.access == "Deny" && rule.destination_port_range == "*" && rule.priority == 200]) == 1 && toset([for rule in azurerm_network_security_group.nodes.security_rule : rule.destination_port_range if rule.access == "Allow"]) == toset(["80", "443", "123"])
    error_message = "Permit reviewed web/time protocols and deny other Internet protocols while preserving VNet paths."
  }
}