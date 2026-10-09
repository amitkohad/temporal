locals {
  cidrs = {
    vnet              = var.environment.network.vnet
    nodes             = var.environment.network.nodes
    postgres          = var.environment.network.postgres
    runner            = var.environment.network.runner
    private_endpoints = var.environment.network.private_endpoints
    services          = var.environment.network.services
    pods              = var.environment.network.pods
  }
  ranges = {
    for name, cidr in local.cidrs : name => {
      first = try(sum([for index, octet in split(".", cidrhost(cidr, 0)) : tonumber(octet) * pow(256, 3 - index)]), 0)
      last  = try(sum([for index, octet in split(".", cidrhost(cidr, -1)) : tonumber(octet) * pow(256, 3 - index)]), 0)
    }
  }
  dns     = try(sum([for index, octet in split(".", var.environment.network.dns_ip) : tonumber(octet) * pow(256, 3 - index)]), 0)
  subnets = ["nodes", "postgres", "runner", "private_endpoints"]
}

output "configuration" {
  value = var.environment
  precondition {
    condition = alltrue([
      for name in local.subnets : local.ranges[name].first >= local.ranges.vnet.first && local.ranges[name].last <= local.ranges.vnet.last
    ])
    error_message = "All platform subnets must fit inside the VNet."
  }
  precondition {
    condition = alltrue(flatten([
      for left in local.subnets : [
        for right in local.subnets : left == right || local.ranges[left].last < local.ranges[right].first || local.ranges[right].last < local.ranges[left].first
      ]
    ]))
    error_message = "Node, database, runner and private endpoint subnets must not overlap."
  }
  precondition {
    condition = alltrue(flatten([
      for left in ["vnet", "services", "pods"] : [
        for right in ["vnet", "services", "pods"] : left == right || local.ranges[left].last < local.ranges[right].first || local.ranges[right].last < local.ranges[left].first
      ]
    ]))
    error_message = "VNet, service and pod ranges must not overlap."
  }
  precondition {
    condition     = local.dns > local.ranges.services.first && local.dns < local.ranges.services.last
    error_message = "Service DNS must be a usable address inside the service CIDR."
  }
}
