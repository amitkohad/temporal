module "resource_group" {
  source   = "../../modules/azure/resource-group"
  mode     = var.resource_group_mode
  location = var.location
  tags     = local.tags
}

locals {
  tags = {
    project     = "nexusflow"
    environment = "stg"
    managed_by  = "terraform"
  }
  // Keep each root in its own container so state roles can be scoped independently.
  state_containers = toset(["bootstrap", "infrastructure", "platform"])
  github_subject   = "repository_id:1411347811:repository_owner_id:19859979:environment:${var.github_environment}:ref:refs/heads/codex/001-azure-temporal-deployment"
  identities       = var.enable_github_federation ? toset(["infrastructure", "registry-writer", "deployment"]) : toset([])
  state_bindings = {
    for pair in setproduct(local.state_containers, var.state_operator_object_ids) :
    "${pair[0]}:${pair[1]}" => { container = pair[0], principal = pair[1] }
  }
}

// ARM-only storage resources avoid opening data-plane access during account bootstrap.
resource "azapi_resource" "state" {
  type      = "Microsoft.Storage/storageAccounts@2023-05-01"
  name      = var.storage_account_name
  parent_id = module.resource_group.reference.id
  location  = var.location
  tags      = local.tags
  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_LRS" }
    properties = {
      minimumTlsVersion            = "TLS1_2"
      supportsHttpsTrafficOnly     = true
      allowBlobPublicAccess        = false
      allowSharedKeyAccess         = false
      allowCrossTenantReplication  = false
      defaultToOAuthAuthentication = true
      publicNetworkAccess          = "Disabled"
      networkAcls                  = { defaultAction = "Deny", bypass = "None" }
      encryption = {
        keySource = "Microsoft.Storage"
        services  = { blob = { enabled = true, keyType = "Account" } }
      }
    }
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "azapi_resource" "blob_service" {
  type      = "Microsoft.Storage/storageAccounts/blobServices@2023-05-01"
  name      = "default"
  parent_id = azapi_resource.state.id
  body = {
    properties = {
      isVersioningEnabled            = true
      deleteRetentionPolicy          = { enabled = true, days = 7 }
      containerDeleteRetentionPolicy = { enabled = true, days = 7 }
    }
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "azapi_resource" "container" {
  for_each  = local.state_containers
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = each.key
  parent_id = azapi_resource.blob_service.id
  body      = { properties = { publicAccess = "None" } }
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_private_dns_zone" "state" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = module.resource_group.reference.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "state" {
  name                  = "nexusflow-state"
  resource_group_name   = module.resource_group.reference.name
  private_dns_zone_name = azurerm_private_dns_zone.state.name
  virtual_network_id    = var.private_network.vnet_id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "state" {
  name                = "pe-nexusflow-state"
  location            = var.location
  resource_group_name = module.resource_group.reference.name
  subnet_id           = var.private_network.subnet_id
  tags                = local.tags
  private_service_connection {
    name                           = "state-blob"
    private_connection_resource_id = azapi_resource.state.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "state"
    private_dns_zone_ids = [azurerm_private_dns_zone.state.id]
  }
}

resource "azurerm_role_assignment" "state_operator" {
  for_each             = local.state_bindings
  scope                = azapi_resource.container[each.value.container].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value.principal
}

resource "azurerm_user_assigned_identity" "github" {
  for_each            = local.identities
  name                = "id-nexusflow-stg-${each.key}"
  location            = var.location
  resource_group_name = module.resource_group.reference.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github" {
  for_each            = local.identities
  name                = "github-staging-branch"
  resource_group_name = module.resource_group.reference.name
  parent_id           = azurerm_user_assigned_identity.github[each.key].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = local.github_subject
}

resource "azurerm_role_assignment" "infrastructure" {
  for_each             = var.enable_github_federation ? toset(["infrastructure"]) : toset([])
  scope                = module.resource_group.reference.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github[each.key].principal_id
}

resource "azurerm_role_assignment" "github_state" {
  for_each             = var.enable_github_federation ? toset(["infrastructure", "deployment"]) : toset([])
  scope                = azapi_resource.container[each.key == "deployment" ? "platform" : "infrastructure"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github[each.key].principal_id
}
