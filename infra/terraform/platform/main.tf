terraform {
  required_version = ">= 1.10.5, < 1.11.0"
}
variable "handoff" {
  description = "Explicit nonsecret infrastructure outputs, supplied after private access verification."
  type = object({
    environment             = string
    source_commit           = string
    private_access_verified = bool
    kubernetes              = object({ name = string, private_fqdn = string, oidc_issuer = string })
    registry                = object({ hostname = string })
    persistence             = object({ hostname = string, port = number, database = string, visibility_database = string, tls_required = bool })
    secret_store            = object({ uri = string })
  })
  validation {
    condition     = contains(["stg", "prod"], var.handoff.environment) && can(regex("^[0-9a-f]{40}$", var.handoff.source_commit))
    error_message = "Handoff requires a selected environment and immutable source commit."
  }
  validation {
    condition     = var.handoff.private_access_verified && var.handoff.persistence.tls_required && var.handoff.persistence.port == 5432 && var.handoff.persistence.database != var.handoff.persistence.visibility_database
    error_message = "Private API/database access must be verified and PostgreSQL must use TLS and separate databases."
  }
  validation {
    condition     = startswith(var.handoff.kubernetes.oidc_issuer, "https://") && startswith(var.handoff.secret_store.uri, "https://") && var.handoff.kubernetes.private_fqdn != "" && var.handoff.registry.hostname != "" && var.handoff.persistence.hostname != ""
    error_message = "Handoff requires actual private endpoints and HTTPS identity/secret-store references."
  }
}
output "deployment_contract" {
  value = var.handoff
}