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
