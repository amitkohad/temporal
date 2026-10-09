mock_provider "azurerm" {}
variables {
  resource_group_name = "rg-nexusflow"
  location            = "centralindia"
  name                = "psql-nexusflow-stg-ci-test"
  tenant_id           = "48d2ccb2-9e24-49cc-921b-89962ed5f85f"
  delegated_subnet_id = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow/subnets/postgresql"
  virtual_network_id  = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow"
  administrator       = { object_id = "11111111-1111-1111-1111-111111111111", principal_name = "operator@example.test" }
}
run "private_entra_staging" {
  command = plan
  assert {
    condition     = !azurerm_postgresql_flexible_server.this.public_network_access_enabled && !azurerm_postgresql_flexible_server.this.authentication[0].password_auth_enabled && azurerm_postgresql_flexible_server.this.authentication[0].active_directory_auth_enabled
    error_message = "PostgreSQL must require private access and Entra authentication."
  }
  assert {
    condition     = azurerm_postgresql_flexible_server.this.sku_name == "B_Standard_B1ms" && azurerm_postgresql_flexible_server.this.storage_mb == 32768 && length(azurerm_postgresql_flexible_server.this.high_availability) == 0 && toset(keys(azurerm_postgresql_flexible_server_database.temporal)) == toset(["temporal", "temporal_visibility"])
    error_message = "Staging must use the small profile and separate databases."
  }
}
run "burstable_ha_rejected" {
  command = plan
  variables { profile = { high_availability_mode = "ZoneRedundant" } }
  expect_failures = [var.profile]
}
run "general_purpose_ha" {
  command = plan
  variables { profile = { sku_name = "GP_Standard_D2s_v3", high_availability_mode = "ZoneRedundant", zone = "1", standby_zone = "2" } }
  assert {
    condition     = azurerm_postgresql_flexible_server.this.high_availability[0].mode == "ZoneRedundant"
    error_message = "HA configuration must be passed to Azure."
  }
}
run "visibility_extension_allowlisted" {
  command = plan
  assert {
    condition     = azurerm_postgresql_flexible_server_configuration.extensions.name == "azure.extensions" && azurerm_postgresql_flexible_server_configuration.extensions.value == "BTREE_GIN"
    error_message = "Visibility schema requires the Azure btree_gin extension allowlist."
  }
}
run "dns_zone_distinct_from_server_fqdn" {
  command = plan
  assert {
    condition     = azurerm_private_dns_zone.postgresql.name != "${azurerm_postgresql_flexible_server.this.name}.postgres.database.azure.com" && azurerm_private_dns_zone.postgresql.name == "private-${var.name}.postgres.database.azure.com"
    error_message = "Azure private DNS zone must differ from the PostgreSQL server FQDN."
  }
}