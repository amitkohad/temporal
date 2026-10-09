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

variable "environment" {
  type = object({
    name               = string
    classification     = string
    prefix             = string
    source_commit      = string
    kubernetes_version = optional(string)
    postgres_version   = optional(string, "17")
    registry_private   = optional(bool, false)
    postgres_ha        = optional(bool, false)
    node_count         = optional(number, 1)
    retention_days     = optional(number, 3)
    recovery_owner     = optional(string)
    rpo_minutes        = optional(number)
    rto_minutes        = optional(number)
    network = object({
      vnet              = string
      nodes             = string
      postgres          = string
      runner            = string
      private_endpoints = string
      services          = string
      pods              = string
      dns_ip            = string
    })
  })
}

variable "registry_sku" {
  description = "Azure-only registry tier; the shared contract expresses privacy instead of provider SKUs."
  type        = string
  default     = "Basic"
  validation {
    condition     = contains(["Basic", "Premium"], var.registry_sku) && (!var.environment.registry_private || var.registry_sku == "Premium")
    error_message = "Azure registry tier must be Basic or Premium; private registry access requires Premium."
  }
}
