variable "provision_platform" {
  description = "Enable resource composition only with resolved platform inputs; contract-only validation remains available."
  type        = bool
  default     = false
}
variable "platform" {
  type = object({
    vnet_id                    = string
    subnet_ids                 = object({ nodes = string, postgres = string, runner = string, private_endpoints = string })
    registry_name              = string
    aks_name                   = string
    node_resource_group_name   = string
    postgres_name              = string
    key_vault_name             = string
    operator                   = object({ object_id = string, principal_name = string })
    runner_object_id           = optional(string)
    registry_writer_object_ids = optional(set(string), [])
    enable_log_analytics       = optional(bool, false)
    postgres_sku               = optional(string, "B_Standard_B1ms")
    postgres_ha_mode           = optional(string)
    postgres_zone              = optional(string)
    postgres_standby_zone      = optional(string)
  })
  default = null
  validation {
    condition     = !var.provision_platform || (var.platform != null && var.environment.kubernetes_version != null)
    error_message = "Provisioning requires resolved platform names, network references, operator and exact Kubernetes version."
  }
  validation {
    condition     = var.platform == null ? true : !var.environment.postgres_ha || (var.platform.postgres_ha_mode != null && !startswith(var.platform.postgres_sku, "B_"))
    error_message = "The accepted HA contract requires a non-burstable PostgreSQL profile and HA mode."
  }
}