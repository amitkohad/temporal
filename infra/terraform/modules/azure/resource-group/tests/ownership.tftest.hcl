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
  location = "centralindia"
}
run "existing_group_not_owned" {
  command = plan
  assert {
    condition     = length(azurerm_resource_group.owned) == 0 && length(data.azurerm_resource_group.existing) == 1 && !output.reference.managed
    error_message = "Existing rg-nexusflow must remain outside Terraform resource ownership."
  }
}
run "explicit_create" {
  command = plan
  variables {
    mode = "create"
  }
  assert {
    condition     = length(azurerm_resource_group.owned) == 1 && length(data.azurerm_resource_group.existing) == 0 && output.reference.managed
    error_message = "Creating a group must be explicit and own only rg-nexusflow."
  }
}
run "wrong_resource_group" {
  command = plan
  variables {
    name = "rg-unrelated"
  }
  expect_failures = [var.name]
}
