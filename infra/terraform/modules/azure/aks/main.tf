variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "node_resource_group_name" { type = string }
variable "location" { type = string }
variable "tenant_id" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["stg", "prod"], var.environment)
    error_message = "Environment must be stg or prod."
  }
}
variable "kubernetes_version" {
  type = string
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Resolve and provide an exact regional GA Kubernetes patch."
  }
}
variable "subnet_id" { type = string }
variable "service_cidr" { type = string }
variable "pod_cidr" { type = string }
variable "dns_service_ip" { type = string }
variable "registry_id" { type = string }
variable "admin_object_ids" {
  type = set(string)
  validation {
    condition     = length(var.admin_object_ids) > 0
    error_message = "At least one Entra administrator principal is required."
  }
}
variable "system_node_count" {
  type    = number
  default = null
  validation {
    condition     = var.system_node_count == null ? true : var.system_node_count >= 1 && floor(var.system_node_count) == var.system_node_count
    error_message = "System node count must be a positive integer."
  }
}
variable "capacity" {
  type = object({
    system_min = optional(number, 3)
    system_max = optional(number, 6)
    user_min   = optional(number, 3)
    user_max   = optional(number, 12)
  })
  default = {}
  validation {
    condition     = var.capacity.system_min >= 3 && var.capacity.system_max >= var.capacity.system_min && var.capacity.user_min >= 3 && var.capacity.user_max >= var.capacity.user_min && alltrue([for n in [var.capacity.system_min, var.capacity.system_max, var.capacity.user_min, var.capacity.user_max] : floor(n) == n])
    error_message = "Production pool bounds must be integers, have at least three nodes, and satisfy min <= max."
  }
}
variable "system_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}
variable "user_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}
variable "production_zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}
variable "tags" {
  type    = map(string)
  default = {}
}
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "id-${var.name}-control"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "id-${var.name}-kubelet"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
resource "azurerm_role_assignment" "network" {
  scope                = split("/subnets/", var.subnet_id)[0]
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
}
resource "azurerm_role_assignment" "kubelet_operator" {
  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
}
resource "azurerm_role_assignment" "pull" {
  scope                = var.registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.kubelet.principal_id
}
resource "azurerm_kubernetes_cluster" "this" {
  name                                = var.name
  location                            = var.location
  resource_group_name                 = var.resource_group_name
  node_resource_group                 = var.node_resource_group_name
  dns_prefix                          = var.name
  kubernetes_version                  = var.kubernetes_version
  sku_tier                            = var.environment == "prod" ? "Standard" : "Free"
  private_cluster_enabled             = true
  private_dns_zone_id                 = "System"
  private_cluster_public_fqdn_enabled = false
  local_account_disabled              = true
  role_based_access_control_enabled   = true
  oidc_issuer_enabled                 = true
  workload_identity_enabled           = true
  node_os_upgrade_channel             = "NodeImage"
  tags                                = var.tags
  azure_active_directory_role_based_access_control {
    tenant_id          = var.tenant_id
    azure_rbac_enabled = true
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }
  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }
  default_node_pool {
    name                         = "system"
    temporary_name_for_rotation  = "sysrotate"
    vm_size                      = var.system_vm_size
    vnet_subnet_id               = var.subnet_id
    node_count                   = coalesce(var.system_node_count, var.environment == "prod" ? var.capacity.system_min : 1)
    auto_scaling_enabled         = var.environment == "prod"
    min_count                    = var.environment == "prod" ? var.capacity.system_min : null
    max_count                    = var.environment == "prod" ? var.capacity.system_max : null
    zones                        = var.environment == "prod" ? var.production_zones : null
    only_critical_addons_enabled = var.environment == "prod"
    os_disk_type                 = "Managed"
    os_disk_size_gb              = 64
    os_sku                       = "Ubuntu"
    max_pods                     = 30
    node_public_ip_enabled       = false
    upgrade_settings { max_surge = "1" }
  }
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    service_cidr        = var.service_cidr
    pod_cidr            = var.pod_cidr
    dns_service_ip      = var.dns_service_ip
    outbound_type       = "loadBalancer"
    load_balancer_sku   = "standard"
    load_balancer_profile { managed_outbound_ip_count = 1 }
  }
  depends_on = [azurerm_role_assignment.network, azurerm_role_assignment.kubelet_operator, azurerm_role_assignment.pull]
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [default_node_pool[0].node_count]
    precondition {
      condition     = var.environment != "prod" || (length(distinct(var.production_zones)) >= 3 && coalesce(var.system_node_count, var.capacity.system_min) >= var.capacity.system_min && coalesce(var.system_node_count, var.capacity.system_min) <= var.capacity.system_max)
      error_message = "Production requires three verified availability zones and system node count within pool bounds."
    }
  }
}
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  count                 = var.environment == "prod" ? 1 : 0
  name                  = "temporal"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_vm_size
  vnet_subnet_id        = var.subnet_id
  mode                  = "User"
  auto_scaling_enabled  = true
  node_count            = var.capacity.user_min
  min_count             = var.capacity.user_min
  max_count             = var.capacity.user_max
  zones                 = var.production_zones
  os_disk_type          = "Managed"
  os_disk_size_gb       = 64
  os_sku                = "Ubuntu"
  max_pods              = 30
  node_labels           = { workload = "temporal" }
  tags                  = var.tags
  upgrade_settings { max_surge = "1" }
  lifecycle { ignore_changes = [node_count] }
}
resource "azurerm_role_assignment" "admin" {
  for_each             = var.admin_object_ids
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}
resource "azurerm_role_assignment" "credentials" {
  for_each             = var.admin_object_ids
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = each.value
}
output "reference" {
  value = {
    id                       = azurerm_kubernetes_cluster.this.id
    name                     = azurerm_kubernetes_cluster.this.name
    private_fqdn             = azurerm_kubernetes_cluster.this.private_fqdn
    oidc_issuer_url          = azurerm_kubernetes_cluster.this.oidc_issuer_url
    kubelet_object_id        = azurerm_user_assigned_identity.kubelet.principal_id
    control_plane_object_id  = azurerm_user_assigned_identity.control_plane.principal_id
    node_resource_group_name = azurerm_kubernetes_cluster.this.node_resource_group
  }
}