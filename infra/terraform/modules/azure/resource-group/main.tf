terraform {
  required_version = ">= 1.10.5, < 1.11.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.50.0"
    }
  }
}

variable "name" {
  type    = string
  default = "rg-nexusflow"
  validation {
    condition     = var.name == "rg-nexusflow"
    error_message = "This deployment must use rg-nexusflow."
  }
}
variable "mode" {
  type    = string
  default = "existing"
  validation {
    condition     = contains(["existing", "create"], var.mode)
    error_message = "Resource group mode must be existing or create."
  }
}
variable "location" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}

data "azurerm_resource_group" "existing" {
  count = var.mode == "existing" ? 1 : 0
  name  = var.name
}

resource "azurerm_resource_group" "owned" {
  count    = var.mode == "create" ? 1 : 0
  name     = var.name
  location = var.location
  tags     = var.tags
  lifecycle {
    prevent_destroy = true
  }
}

output "reference" {
  value = {
    id       = var.mode == "existing" ? data.azurerm_resource_group.existing[0].id : azurerm_resource_group.owned[0].id
    name     = var.name
    location = var.mode == "existing" ? data.azurerm_resource_group.existing[0].location : azurerm_resource_group.owned[0].location
    managed  = var.mode == "create"
  }
}
