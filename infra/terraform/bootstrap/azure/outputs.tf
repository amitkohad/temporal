output "backend_contract" {
  description = "Nonsecret backend configuration. Authentication is supplied through environment variables."
  value = {
    resource_group_name  = module.resource_group.reference.name
    storage_account_name = var.storage_account_name
    use_azuread_auth     = true
    roots = {
      for root in local.state_containers : root => {
        container_name = root
        key            = "nexusflow/stg/${root}.tfstate"
      }
    }
  }
}
output "github_identities" {
  description = "Azure adapter IDs only; no tokens, keys or kubeconfig."
  value = {
    for name, identity in azurerm_user_assigned_identity.github : name => {
      client_id = identity.client_id
      object_id = identity.principal_id
      subject   = local.github_subject
    }
  }
}
