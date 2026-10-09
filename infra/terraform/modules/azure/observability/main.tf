variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name" { type = string }
variable "enable_log_analytics" {
  type    = bool
  default = false
}
variable "alerts" {
  type = map(object({
    scopes           = list(string)
    metric_namespace = string
    metric_name      = string
    aggregation      = string
    operator         = string
    threshold        = number
    action_group_ids = set(string)
  }))
  default = {}
  validation {
    condition     = alltrue([for alert in values(var.alerts) : length(alert.scopes) > 0 && length(alert.action_group_ids) > 0])
    error_message = "Alerts require real resource scopes and at least one existing owner action group."
  }
}
variable "tags" {
  type    = map(string)
  default = {}
}
resource "azurerm_log_analytics_workspace" "this" {
  count               = var.enable_log_analytics ? 1 : 0
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.1
  tags                = var.tags
}
resource "azurerm_monitor_metric_alert" "this" {
  for_each            = var.alerts
  name                = "${var.name}-${each.key}"
  resource_group_name = var.resource_group_name
  scopes              = each.value.scopes
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  criteria {
    metric_namespace = each.value.metric_namespace
    metric_name      = each.value.metric_name
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }
  dynamic "action" {
    for_each = each.value.action_group_ids
    content { action_group_id = action.value }
  }
  tags = var.tags
}
output "reference" {
  value = {
    workspace_id = try(azurerm_log_analytics_workspace.this[0].id, null)
    alert_ids    = { for key, alert in azurerm_monitor_metric_alert.this : key => alert.id }
  }
}
variable "diagnostic_targets" {
  type = map(object({
    resource_id    = string
    log_categories = set(string)
    metrics        = optional(set(string), [])
  }))
  default = {}
  validation {
    condition     = alltrue([for target in values(var.diagnostic_targets) : can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/[^/]+/.+$", target.resource_id)) && length(target.log_categories) + length(target.metrics) > 0 && alltrue([for category in setunion(target.log_categories, target.metrics) : trimspace(category) != ""])])
    error_message = "Diagnostic targets require resource IDs and explicit supported log or metric categories."
  }
}
resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each                   = var.enable_log_analytics ? var.diagnostic_targets : {}
  name                       = "${var.name}-${each.key}"
  target_resource_id         = each.value.resource_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id
  dynamic "enabled_log" {
    for_each = each.value.log_categories
    content { category = enabled_log.value }
  }
  dynamic "enabled_metric" {
    for_each = each.value.metrics
    content { category = enabled_metric.value }
  }
}