mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      id       = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow"
      name     = "rg-nexusflow"
      location = "centralindia"
    }
  }
}

mock_provider "azapi" {}

override_resource {
  target = azapi_resource.state
  values = {
    id = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Storage/storageAccounts/stnexusflowtf7c5841"
  }
}
override_resource {
  target = azapi_resource.blob_service
  values = {
    id = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Storage/storageAccounts/stnexusflowtf7c5841/blobServices/default"
  }
}

variables {
  subscription_id           = "aa228172-c4ae-4c29-bd05-dcdcebb70ff4"
  tenant_id                 = "48d2ccb2-9e24-49cc-921b-89962ed5f85f"
  state_operator_object_ids = ["11111111-1111-1111-1111-111111111111"]
  private_network = {
    vnet_id   = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow"
    subnet_id = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow/subnets/private-endpoints"
  }
}
run "private_state" {
  command = plan
  assert {
    condition = (
      azapi_resource.state.body.properties.publicNetworkAccess == "Disabled" &&
      !azapi_resource.state.body.properties.allowSharedKeyAccess &&
      !azapi_resource.state.body.properties.allowBlobPublicAccess &&
      azapi_resource.state.body.properties.supportsHttpsTrafficOnly &&
      azapi_resource.state.body.properties.minimumTlsVersion == "TLS1_2"
    )
    error_message = "State must use private, encrypted, identity-only access."
  }
  assert {
    condition     = azapi_resource.blob_service.body.properties.isVersioningEnabled && azapi_resource.blob_service.body.properties.deleteRetentionPolicy.days == 7 && azapi_resource.blob_service.body.properties.containerDeleteRetentionPolicy.days == 7
    error_message = "State must retain versions and deleted blobs/containers."
  }
  assert {
    condition     = length(azapi_resource.container) == 3 && alltrue([for container in azapi_resource.container : container.body.properties.publicAccess == "None"])
    error_message = "All three isolated state containers must be private."
  }
  assert {
    condition     = length(azurerm_user_assigned_identity.github) == 0 && length(azurerm_federated_identity_credential.github) == 0
    error_message = "OIDC trust must not be enabled implicitly."
  }
}
run "explicit_federation" {
  command = plan
  variables {
    enable_github_federation = true
  }
  assert {
    condition = alltrue([
      for credential in azurerm_federated_identity_credential.github :
      credential.subject == "repository_id:1411347811:repository_owner_id:19859979:environment:staging:ref:refs/heads/codex/001-azure-temporal-deployment" &&
      credential.issuer == "https://token.actions.githubusercontent.com" &&
      length(credential.audience) == 1 && contains(credential.audience, "api://AzureADTokenExchange")
    ])
    error_message = "Federation must bind the repository, protected environment and exact authoritative branch."
  }
  assert {
    condition     = length(azurerm_role_assignment.github_state) == 2 && !contains(keys(azurerm_role_assignment.github_state), "registry-writer")
    error_message = "Registry publishing must not receive Terraform state privileges."
  }
}
run "untrusted_environment" {
  command = plan
  variables {
    github_environment = "pull_request"
  }
  expect_failures = [var.github_environment]
}
run "invalid_storage_name" {
  command = plan
  variables {
    storage_account_name = "Public-State-With-Hyphens"
  }
  expect_failures = [var.storage_account_name]
}
run "missing_state_operator" {
  command = plan
  variables {
    state_operator_object_ids = []
  }
  expect_failures = [var.state_operator_object_ids]
}
run "subnet_from_another_vnet" {
  command = plan
  variables {
    private_network = {
      vnet_id   = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow"
      subnet_id = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/unrelated/subnets/private-endpoints"
    }
  }
  expect_failures = [var.private_network]
}
