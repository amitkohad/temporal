mock_provider "azurerm" {}
variables {
  name                = "acrnexusflowtest"
  resource_group_name = "rg-nexusflow"
  location            = "centralindia"
}
run "basic_authenticated_public" {
  command = plan
  assert {
    condition     = azurerm_container_registry.this.sku == "Basic" && !azurerm_container_registry.this.admin_enabled && !azurerm_container_registry.this.anonymous_pull_enabled && azurerm_container_registry.this.public_network_access_enabled && length(azurerm_private_endpoint.this) == 0
    error_message = "Staging requires low-cost Basic with Entra authentication."
  }
}
run "basic_private_rejected" {
  command = plan
  variables { private_access = true }
  expect_failures = [azurerm_container_registry.this]
}
run "premium_private" {
  command = plan
  variables {
    sku                        = "Premium"
    private_access             = true
    private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/test/subnets/private"
    virtual_network_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/test"
  }
  assert {
    condition     = !azurerm_container_registry.this.public_network_access_enabled && length(azurerm_private_endpoint.this) == 1 && azurerm_private_dns_zone_virtual_network_link.this[0].registration_enabled == false
    error_message = "Production registry requires private connectivity and DNS."
  }
}