mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-nexusflow/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test"
      principal_id = "11111111-1111-1111-1111-111111111111"
      client_id    = "22222222-2222-2222-2222-222222222222"
    }
  }
  mock_resource "azurerm_kubernetes_cluster" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-nexusflow/providers/Microsoft.ContainerService/managedClusters/test" }
  }
}
variables {
  name                     = "aks-nexusflow-test"
  resource_group_name      = "rg-nexusflow"
  node_resource_group_name = "rg-nexusflow-test-nodes"
  location                 = "centralindia"
  tenant_id                = "00000000-0000-0000-0000-000000000000"
  environment              = "stg"
  kubernetes_version       = "1.35.8"
  subnet_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/test/subnets/aks"
  service_cidr             = "10.43.0.0/16"
  pod_cidr                 = "10.44.0.0/16"
  dns_service_ip           = "10.43.0.10"
  registry_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-nexusflow/providers/Microsoft.ContainerRegistry/registries/test"
  admin_object_ids         = ["33333333-3333-3333-3333-333333333333"]
}
run "private_staging_security_and_cost" {
  command = plan
  assert {
    condition     = azurerm_kubernetes_cluster.this.private_cluster_enabled && !azurerm_kubernetes_cluster.this.private_cluster_public_fqdn_enabled && azurerm_kubernetes_cluster.this.local_account_disabled && azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].azure_rbac_enabled && azurerm_kubernetes_cluster.this.oidc_issuer_enabled && azurerm_kubernetes_cluster.this.workload_identity_enabled
    error_message = "API access must remain private with Entra and workload identities."
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.sku_tier == "Free" && azurerm_kubernetes_cluster.this.default_node_pool[0].node_count == 1 && !azurerm_kubernetes_cluster.this.default_node_pool[0].auto_scaling_enabled && length(azurerm_kubernetes_cluster_node_pool.user) == 0
    error_message = "Staging shares one node and avoids paid control-plane tier."
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_plugin_mode == "overlay" && azurerm_kubernetes_cluster.this.network_profile[0].network_data_plane == "cilium" && azurerm_kubernetes_cluster.this.network_profile[0].outbound_type == "loadBalancer" && azurerm_role_assignment.pull.role_definition_name == "AcrPull" && azurerm_role_assignment.network.scope == split("/subnets/", var.subnet_id)[0]
    error_message = "Overlay policies, explicit outbound and scoped identity access are required."
  }
}
run "production_separate_zoned_pools" {
  command = plan
  variables { environment = "prod" }
  assert {
    condition     = azurerm_kubernetes_cluster.this.sku_tier == "Standard" && azurerm_kubernetes_cluster.this.default_node_pool[0].only_critical_addons_enabled && azurerm_kubernetes_cluster.this.default_node_pool[0].auto_scaling_enabled && length(azurerm_kubernetes_cluster.this.default_node_pool[0].zones) == 3 && azurerm_kubernetes_cluster_node_pool.user[0].min_count == 3 && azurerm_kubernetes_cluster_node_pool.user[0].auto_scaling_enabled
    error_message = "Production requires separate autoscaling pools across zones."
  }
}
run "minor_version_rejected" {
  command = plan
  variables { kubernetes_version = "1.35" }
  expect_failures = [var.kubernetes_version]
}
run "no_admin_rejected" {
  command = plan
  variables { admin_object_ids = [] }
  expect_failures = [var.admin_object_ids]
}
run "explicit_contract_count" {
  command = plan
  variables { system_node_count = 2 }
  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].node_count == 2
    error_message = "The environment's node count must reach the system pool configuration."
  }
}
run "production_count_outside_bounds_rejected" {
  command = plan
  variables {
    environment       = "prod"
    system_node_count = 2
  }
  expect_failures = [azurerm_kubernetes_cluster.this]
}
run "inverted_pool_bounds_rejected" {
  command = plan
  variables { capacity = { system_min = 6, system_max = 3 } }
  expect_failures = [var.capacity]
}