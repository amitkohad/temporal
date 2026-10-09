locals {
  platform_enabled = var.provision_platform ? { (var.environment.name) = var.platform } : {}
  tags             = { project = module.configuration.configuration.prefix, environment = module.configuration.configuration.name, managed_by = "terraform" }
}
module "registry" {
  for_each                   = local.platform_enabled
  source                     = "../../modules/azure/registry"
  name                       = each.value.registry_name
  resource_group_name        = module.resource_group.reference.name
  location                   = var.location
  sku                        = var.registry_sku
  private_access             = module.configuration.configuration.registry_private
  private_endpoint_subnet_id = each.value.subnet_ids.private_endpoints
  virtual_network_id         = each.value.vnet_id
  writer_object_ids          = each.value.registry_writer_object_ids
  tags                       = local.tags
}
module "aks" {
  for_each                 = local.platform_enabled
  source                   = "../../modules/azure/aks"
  name                     = each.value.aks_name
  node_resource_group_name = each.value.node_resource_group_name
  resource_group_name      = module.resource_group.reference.name
  location                 = var.location
  tenant_id                = var.tenant_id
  environment              = module.configuration.configuration.name
  system_node_count        = module.configuration.configuration.node_count
  kubernetes_version       = module.configuration.configuration.kubernetes_version
  subnet_id                = each.value.subnet_ids.nodes
  service_cidr             = module.configuration.configuration.network.services
  pod_cidr                 = module.configuration.configuration.network.pods
  dns_service_ip           = module.configuration.configuration.network.dns_ip
  registry_id              = module.registry[each.key].reference.id
  admin_object_ids         = toset(concat([each.value.operator.object_id], each.value.runner_object_id == null ? [] : [each.value.runner_object_id]))
  tags                     = local.tags
}
module "postgresql" {
  for_each            = local.platform_enabled
  source              = "../../modules/azure/postgresql"
  name                = each.value.postgres_name
  resource_group_name = module.resource_group.reference.name
  location            = var.location
  tenant_id           = var.tenant_id
  delegated_subnet_id = each.value.subnet_ids.postgres
  virtual_network_id  = each.value.vnet_id
  administrator       = each.value.operator
  profile = {
    version                = module.configuration.configuration.postgres_version
    sku_name               = each.value.postgres_sku
    high_availability_mode = module.configuration.configuration.postgres_ha ? each.value.postgres_ha_mode : null
    zone                   = each.value.postgres_zone
    standby_zone           = each.value.postgres_standby_zone
  }
  tags = local.tags
}
module "security" {
  for_each                   = local.platform_enabled
  source                     = "../../modules/azure/security"
  name                       = each.value.key_vault_name
  resource_group_name        = module.resource_group.reference.name
  location                   = var.location
  tenant_id                  = var.tenant_id
  private_endpoint_subnet_id = each.value.subnet_ids.private_endpoints
  virtual_network_id         = each.value.vnet_id
  secret_operator_object_ids = [each.value.operator.object_id]
  secret_reader_object_ids   = each.value.runner_object_id == null ? [] : [each.value.runner_object_id]
  tags                       = local.tags
}
module "observability" {
  for_each             = local.platform_enabled
  source               = "../../modules/azure/observability"
  name                 = "logs-nexusflow-stg-ci"
  resource_group_name  = module.resource_group.reference.name
  location             = var.location
  enable_log_analytics = each.value.enable_log_analytics
  diagnostic_targets = each.value.enable_log_analytics ? {
    aks      = { resource_id = module.aks[each.key].reference.id, log_categories = toset(["kube-audit-admin"]), metrics = toset([]) }
    postgres = { resource_id = module.postgresql[each.key].reference.id, log_categories = toset(["PostgreSQLLogs"]), metrics = toset([]) }
    vault    = { resource_id = module.security[each.key].reference.id, log_categories = toset(["AuditEvent"]), metrics = toset([]) }
  } : {}
  tags = local.tags
}
output "platform_references" {
  value = {
    for name, platform in local.platform_enabled : name => {
      registry      = module.registry[name].reference
      kubernetes    = module.aks[name].reference
      persistence   = module.postgresql[name].reference
      secret_store  = module.security[name].reference
      observability = module.observability[name].reference
    }
  }
}
resource "azurerm_role_assignment" "runner_reader" {
  for_each             = { for name, platform in local.platform_enabled : name => platform if platform.runner_object_id != null }
  scope                = module.resource_group.reference.id
  role_definition_name = "Reader"
  principal_id         = each.value.runner_object_id
}

variable "enable_network_bootstrap" {
  description = "Temporary write grant on the existing runner NSG only; disable immediately after the reviewed rule update."
  type        = bool
  default     = false
}
resource "azurerm_role_assignment" "runner_network_bootstrap" {
  for_each             = { for name, platform in local.platform_enabled : name => platform if var.enable_network_bootstrap && platform.runner_object_id != null }
  scope                = "${module.resource_group.reference.id}/providers/Microsoft.Network/networkSecurityGroups/nsg-vm-nexusflow-stg-ci-runner"
  role_definition_name = "Network Contributor"
  principal_id         = each.value.runner_object_id
}

module "network" {
  for_each            = local.platform_enabled
  source              = "../../modules/azure/network"
  resource_group_name = module.resource_group.reference.name
  location            = var.location
  nodes_subnet_id     = each.value.subnet_ids.nodes
  tags                = local.tags
}
