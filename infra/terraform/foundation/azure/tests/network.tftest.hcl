mock_provider "azurerm" {}
mock_provider "azapi" {}
variables {
  subscription_id = "aa228172-c4ae-4c29-bd05-dcdcebb70ff4"
  tenant_id       = "48d2ccb2-9e24-49cc-921b-89962ed5f85f"
  environment = {
    name             = "stg"
    classification   = "staging"
    prefix           = "nexusflow"
    source_commit    = "717f485c760d1068aa310906466468e51120254f"
    postgres_version = "17"
    network = {
      vnet              = "10.42.0.0/16"
      nodes             = "10.42.0.0/23"
      postgres          = "10.42.2.0/27"
      runner            = "10.42.3.0/27"
      private_endpoints = "10.42.4.0/27"
      services          = "10.43.0.0/16"
      pods              = "10.44.0.0/16"
      dns_ip            = "10.43.0.10"
    }
  }
}
run "isolated_private_foundation" {
  command = plan
  assert {
    condition     = length(azurerm_subnet.foundation) == 4 && alltrue([for subnet in azurerm_subnet.foundation : !subnet.default_outbound_access_enabled]) && azurerm_subnet.foundation["postgres"].delegation[0].service_delegation[0].name == "Microsoft.DBforPostgreSQL/flexibleServers"
    error_message = "Foundation must separate the four subnet roles and delegate PostgreSQL."
  }
  assert {
    condition     = one(azurerm_network_security_group.runner.security_rule).access == "Deny" && one(azurerm_network_security_group.runner.security_rule).direction == "Inbound"
    error_message = "Runner subnet must reject inbound connections."
  }
}