variable "environment" {
  description = "Provider-neutral environment inputs. No credentials or Azure resource IDs belong here."
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

  validation {
    condition     = contains(["stg", "prod"], var.environment.name) && contains(["staging", "production"], var.environment.classification) && (var.environment.name == "prod") == (var.environment.classification == "production")
    error_message = "Environment must pair stg/staging or prod/production."
  }
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.environment.prefix))
    error_message = "Prefix must contain 3–12 lowercase alphanumeric characters, starting with a letter."
  }
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.environment.source_commit))
    error_message = "Source must be a full lowercase immutable Git commit."
  }
  validation {
    condition     = var.environment.kubernetes_version == null ? true : can(regex("^1\\.[0-9]+\\.[0-9]+$", var.environment.kubernetes_version))
    error_message = "Kubernetes version must be null while unresolved or an exact major.minor.patch version."
  }
  validation {
    condition     = contains(["16", "17", "18"], var.environment.postgres_version)
    error_message = "PostgreSQL must use a reviewed compatibility candidate (16, 17 or 18); regional support still needs preflight."
  }
  validation {
    condition     = var.environment.node_count >= 1 && floor(var.environment.node_count) == var.environment.node_count && var.environment.retention_days >= 1 && floor(var.environment.retention_days) == var.environment.retention_days
    error_message = "Node count and workflow retention must be positive integers."
  }
  validation {
    condition = var.environment.classification != "production" ? true : (
      var.environment.registry_private && var.environment.postgres_ha && var.environment.node_count >= 3 &&
      var.environment.kubernetes_version != null &&
      try(length(trimspace(var.environment.recovery_owner)) > 0, false) &&
      try(var.environment.rpo_minutes > 0 && var.environment.rto_minutes > 0, false)
    )
    error_message = "Production requires a private registry, database HA, at least three nodes, an exact Kubernetes version, recovery owner and positive RPO/RTO."
  }
  validation {
    condition = alltrue([
      for cidr in [
        var.environment.network.vnet, var.environment.network.nodes, var.environment.network.postgres,
        var.environment.network.runner, var.environment.network.private_endpoints,
        var.environment.network.services, var.environment.network.pods
      ] : can(cidrnetmask(cidr)) && try(cidrhost(cidr, 0) == split("/", cidr)[0], false)
    ])
    error_message = "Network ranges must be canonical IPv4 CIDRs."
  }
  validation {
    condition     = can(cidrnetmask("${var.environment.network.dns_ip}/32"))
    error_message = "Service DNS must be an IPv4 address."
  }
}
