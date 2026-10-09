module "configuration" {
  source      = "../../modules/contracts"
  environment = var.environment
}

module "resource_group" {
  source   = "../../modules/azure/resource-group"
  mode     = var.resource_group_mode
  location = var.location
  tags = {
    project     = module.configuration.configuration.prefix
    environment = module.configuration.configuration.name
    managed_by  = "terraform"
  }
}

locals {
  state_keys = {
    bootstrap      = "${module.configuration.configuration.prefix}/${module.configuration.configuration.name}/bootstrap.tfstate"
    infrastructure = "${module.configuration.configuration.prefix}/${module.configuration.configuration.name}/infrastructure.tfstate"
    platform       = "${module.configuration.configuration.prefix}/${module.configuration.configuration.name}/platform.tfstate"
  }
}
