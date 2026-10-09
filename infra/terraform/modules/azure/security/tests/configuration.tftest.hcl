mock_provider "azurerm" {}
variables {
  resource_group_name        = "rg-nexusflow"
  location                   = "centralindia"
  name                       = "kv-nxf-stg-ci-test"
  tenant_id                  = "48d2ccb2-9e24-49cc-921b-89962ed5f85f"
  private_endpoint_subnet_id = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow/subnets/endpoints"
  virtual_network_id         = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow"
}
run "private_vault" {
  command = plan
  assert {
    condition     = !azurerm_key_vault.this.public_network_access_enabled && azurerm_key_vault.this.rbac_authorization_enabled && azurerm_key_vault.this.purge_protection_enabled && azurerm_key_vault.this.network_acls[0].bypass == "None"
    error_message = "Vault requires private access, RBAC, and purge protection."
  }
}
run "scoped_reader" {
  command = plan
  variables { secret_reader_object_ids = ["11111111-1111-1111-1111-111111111111"] }
  assert {
    condition     = azurerm_role_assignment.reader["11111111-1111-1111-1111-111111111111"].role_definition_name == "Key Vault Secrets User" && length(azurerm_role_assignment.operator) == 0
    error_message = "Secret readers must not receive write access."
  }
}