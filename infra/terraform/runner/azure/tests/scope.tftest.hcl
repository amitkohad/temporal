mock_provider "azurerm" {}
variables {
  subscription_id = "aa228172-c4ae-4c29-bd05-dcdcebb70ff4"
  tenant_id       = "48d2ccb2-9e24-49cc-921b-89962ed5f85f"
  subnet_id       = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4/resourceGroups/rg-nexusflow/providers/Microsoft.Network/virtualNetworks/vnet-nexusflow-stg-ci/subnets/snet-runner"
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgKVqaTWpBTxGFs5Luu4gPJTSMxtgGr12v5L9OmNyAZ"
}
run "disabled_has_no_roles" {
  command = plan
  assert {
    condition     = output.runner == null && length(azurerm_role_assignment.state) == 0
    error_message = "Disabled runner has no identity grants."
  }
}
run "reject_subscription_scope" {
  command = plan
  variables {
    state_container_ids = { infrastructure = "/subscriptions/aa228172-c4ae-4c29-bd05-dcdcebb70ff4" }
  }
  expect_failures = [var.state_container_ids]
}