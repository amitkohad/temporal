mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      id       = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow"
      name     = "rg-nexusflow"
      location = "centralindia"
    }
  }
}

variables {
  subscription_id = "aa228172-c4ae-4c29-bd05-dcdcebb70ff4"
  tenant_id       = "48d2ccb2-9e24-49cc-921b-89962ed5f85f"
  environment = {
    name           = "stg"
    classification = "staging"
    prefix         = "nexusflow"
    source_commit  = "717f485c760d1068aa310906466468e51120254f"
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
run "reference_shared_group" {
  command = plan
  assert {
    condition     = !output.azure_scope.resource_group.managed && output.azure_scope.resource_group.name == "rg-nexusflow"
    error_message = "Existing mode must not manage or claim the shared resource group."
  }
  assert {
    condition     = length(distinct(values(output.state_keys))) == 3
    error_message = "Each root must have a distinct state key."
  }
}
run "create_owned_group" {
  command = plan
  variables {
    resource_group_mode = "create"
  }
  assert {
    condition     = output.azure_scope.resource_group.managed && output.azure_scope.resource_group.name == "rg-nexusflow"
    error_message = "Create mode must own exactly one group and not read an existing group."
  }
}
run "invalid_group_mode" {
  command = plan
  variables {
    resource_group_mode = "import-and-destroy"
  }
  expect_failures = [var.resource_group_mode]
}
run "invalid_subscription" {
  command = plan
  variables {
    subscription_id = "implicit"
  }
  expect_failures = [var.subscription_id]
}

run "private_registry_cannot_use_basic" {
  command = plan
  variables {
    environment = merge(run.reference_shared_group.environment_contract, { registry_private = true })
  }
  expect_failures = [var.registry_sku]
}
run "resolved_staging_composition" {
  command = plan
  variables {
    provision_platform = true
    environment        = merge(run.reference_shared_group.environment_contract, { kubernetes_version = "1.35.8" })
    platform = {
      vnet_id = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow-stg-ci"
      subnet_ids = {
        nodes             = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow-stg-ci/subnets/snet-nodes"
        postgres          = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow-stg-ci/subnets/snet-postgres"
        runner            = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow-stg-ci/subnets/snet-runner"
        private_endpoints = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow-stg-ci/subnets/snet-private-endpoints"
      }
      registry_name            = "acrnexusflowstgci7c5841"
      aks_name                 = "aks-nexusflow-stg-ci"
      node_resource_group_name = "rg-nexusflow-aks-stg-ci-nodes"
      postgres_name            = "psql-nexusflow-stg-ci-7c5841"
      key_vault_name           = "kv-nxf-stg-ci-7c5841"
      operator                 = { object_id = "11111111-1111-1111-1111-111111111111", principal_name = "operator@example.test" }
    }
  }
  assert {
    condition     = !output.platform_references.stg.registry.private_access && output.platform_references.stg.persistence.authentication == "EntraOnly" && output.platform_references.stg.observability.workspace_id == null
    error_message = "Staging composition must preserve approved registry access, credential-free provisioning and minimal paid monitoring."
  }
}
