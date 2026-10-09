mock_provider "azurerm" {}
variables {
  resource_group_name = "rg-nexusflow"
  location            = "centralindia"
  name                = "log-nexusflow-stg"
}
run "no_unrequested_cost" {
  command = plan
  assert {
    condition     = length(azurerm_log_analytics_workspace.this) == 0 && length(azurerm_monitor_metric_alert.this) == 0
    error_message = "Default staging must not create paid log ingestion or alerts."
  }
}
run "missing_alert_owner_rejected" {
  command = plan
  variables {
    alerts = { cpu = { scopes = ["/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-test"], metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers", metric_name = "cpu_percent", aggregation = "Average", operator = "GreaterThan", threshold = 80, action_group_ids = [] } }
  }
  expect_failures = [var.alerts]
}
run "opt_in_log_retention" {
  command = plan
  variables { enable_log_analytics = true }
  assert {
    condition     = azurerm_log_analytics_workspace.this[0].retention_in_days == 30 && azurerm_log_analytics_workspace.this[0].daily_quota_gb == 0.1
    error_message = "Opt-in logs must keep bounded ingestion and retention."
  }
}
run "diagnostics_disabled" {
  command = plan
  variables {
    diagnostic_targets = { vault = { resource_id = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.KeyVault/vaults/kv-test", log_categories = ["AuditEvent"] } }
  }
  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "Diagnostic settings must not exist without opt-in Log Analytics."
  }
}
run "diagnostics_explicit_categories" {
  command = plan
  variables {
    enable_log_analytics = true
    diagnostic_targets   = { vault = { resource_id = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.KeyVault/vaults/kv-test", log_categories = ["AuditEvent"] } }
  }
  assert {
    condition     = azurerm_monitor_diagnostic_setting.this["vault"].target_resource_id == var.diagnostic_targets.vault.resource_id && toset([for log in azurerm_monitor_diagnostic_setting.this["vault"].enabled_log : log.category]) == toset(["AuditEvent"]) && length(azurerm_monitor_diagnostic_setting.this["vault"].enabled_metric) == 0
    error_message = "Diagnostic settings must use only the explicitly requested categories and resource."
  }
}
run "invalid_diagnostic_target_rejected" {
  command = plan
  variables {
    enable_log_analytics = true
    diagnostic_targets   = { vault = { resource_id = "placeholder", log_categories = ["AuditEvent"] } }
  }
  expect_failures = [var.diagnostic_targets]
}