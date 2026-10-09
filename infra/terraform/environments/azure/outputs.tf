output "environment_contract" {
  description = "Validated configuration, not provisioned platform endpoints."
  value       = module.configuration.configuration
}
output "azure_scope" {
  description = "Azure adapter metadata; do not pass provider IDs into shared Temporal values."
  value = {
    subscription_id = var.subscription_id
    tenant_id       = var.tenant_id
    location        = var.location
    registry_sku    = var.registry_sku
    resource_group  = module.resource_group.reference
  }
}
output "state_keys" {
  value = local.state_keys
}
