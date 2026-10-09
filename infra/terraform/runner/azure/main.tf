terraform {
  required_version = ">= 1.10.5, < 1.11.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "= 4.50.0" }
  }
}
provider "azurerm" {
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
  storage_use_azuread             = true
  features {}
}
variable "subscription_id" { type = string }
variable "tenant_id" { type = string }
variable "location" {
  type    = string
  default = "centralindia"
}
variable "enabled" {
  type    = bool
  default = false
}
variable "subnet_id" { type = string }
variable "ssh_public_key" {
  type    = string
  default = ""
}
variable "vm_size" {
  type    = string
  default = "Standard_B1ms"
}
variable "image_version" {
  type    = string
  default = "latest"
}
variable "state_container_ids" {
  type    = map(string)
  default = {}
  validation {
    condition     = alltrue([for root, scope in var.state_container_ids : contains(["bootstrap", "infrastructure", "platform"], root) && can(regex("^/subscriptions/[^/]+/resourceGroups/rg-nexusflow/providers/Microsoft.Storage/storageAccounts/[a-z0-9]+/blobServices/default/containers/${root}$", scope))])
    error_message = "Grant state access only to the three rg-nexusflow backend containers."
  }
}
module "runner" {
  source              = "../../modules/azure/runner"
  enabled             = var.enabled
  resource_group_name = "rg-nexusflow"
  location            = var.location
  subnet_id           = var.subnet_id
  ssh_public_key      = var.ssh_public_key
  vm_size             = var.vm_size
  image_version       = var.image_version
  tags                = { project = "nexusflow", environment = "stg", managed_by = "terraform", purpose = "attended-private-operator" }
}
resource "azurerm_role_assignment" "state" {
  for_each             = var.enabled ? var.state_container_ids : {}
  scope                = each.value
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.runner.reference.principal_id
}
output "runner" { value = module.runner.reference }