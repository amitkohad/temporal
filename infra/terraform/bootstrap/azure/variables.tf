variable "subscription_id" {
  description = "Explicit target subscription; never infer a write target from CLI defaults."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "Subscription ID must be a UUID."
  }
}
variable "tenant_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "Tenant ID must be a UUID."
  }
}
variable "location" {
  type    = string
  default = "centralindia"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Location must be an Azure location identifier; availability still needs preflight."
  }
}
variable "resource_group_mode" {
  type    = string
  default = "existing"
  validation {
    condition     = contains(["existing", "create"], var.resource_group_mode)
    error_message = "Resource group mode must be existing or create."
  }
}

variable "storage_account_name" {
  type    = string
  default = "stnexusflowtf7c5841"
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account names require 3–24 lowercase letters or digits."
  }
}
variable "private_network" {
  description = "An existing private-access foundation. Provision it from protected local state before backend bootstrap."
  type = object({
    subnet_id = string
    vnet_id   = string
  })
  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_network.subnet_id)) && can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+$", var.private_network.vnet_id)) && startswith(var.private_network.subnet_id, "${var.private_network.vnet_id}/subnets/")
    error_message = "Private endpoint subnet must belong to the supplied VNet."
  }
}
variable "state_operator_object_ids" {
  description = "Human/bootstrap principals requiring container-scoped state access. No storage keys are accepted."
  type        = set(string)
  validation {
    condition     = length(var.state_operator_object_ids) > 0 && alltrue([for id in var.state_operator_object_ids : can(regex("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", id))])
    error_message = "At least one state operator object UUID must be supplied."
  }
}
variable "enable_github_federation" {
  description = "Enable only after GitHub custom OIDC subject and protected environment are configured."
  type        = bool
  default     = false
}
variable "github_environment" {
  type    = string
  default = "staging"
  validation {
    condition     = var.github_environment == "staging"
    error_message = "The current bootstrap trusts only the protected staging environment."
  }
}
