variables {
  environment = {
    name           = "stg"
    classification = "staging"
    prefix         = "nexusflow"
    source_commit  = "717f485c760d1068aa310906466468e51120254f"
    network = {
      vnet              = "10.42.0.0/16"
      nodes             = "10.42.0.0/23"
      postgres          = "10.42.2.0/27"
      runner            = "10.42.3.0/27"
      private_endpoints = "10.42.4.0/27"
      services          = "10.43.0.0/16"
      pods              = "10.44.0.0/16"
      dns_ip            = "10.43.0.10"
    }
  }
}

run "staging_defaults" {
  command = plan
  assert {
    condition     = output.configuration.node_count == 1 && !output.configuration.registry_private && !output.configuration.postgres_ha
    error_message = "Staging must preserve the selected low-cost defaults."
  }
}

run "mutable_source" {
  command = plan
  variables {
    environment = merge(run.staging_defaults.configuration, { source_commit = "main" })
  }
  expect_failures = [var.environment]
}

run "production_without_recovery" {
  command = plan
  variables {
    environment = merge(run.staging_defaults.configuration, { name = "prod", classification = "production" })
  }
  expect_failures = [var.environment]
}

run "invalid_version" {
  command = plan
  variables {
    environment = merge(run.staging_defaults.configuration, { kubernetes_version = "latest" })
  }
  expect_failures = [var.environment]
}

run "invalid_postgres" {
  command = plan
  variables {
    environment = merge(run.staging_defaults.configuration, { postgres_version = "12" })
  }
  expect_failures = [var.environment]
}

run "invalid_node_count" {
  command = plan
  variables {
    environment = merge(run.staging_defaults.configuration, { node_count = 0 })
  }
  expect_failures = [var.environment]
}

run "overlapping_subnets" {
  command = plan
  variables {
    environment = merge(run.staging_defaults.configuration, { network = merge(run.staging_defaults.configuration.network, { runner = "10.42.2.0/27" }) })
  }
  expect_failures = [output.configuration]
}

run "subnet_outside_vnet" {
  command = plan
  variables {
    environment = merge(run.staging_defaults.configuration, { network = merge(run.staging_defaults.configuration.network, { runner = "10.46.0.0/27" }) })
  }
  expect_failures = [output.configuration]
}

run "overlapping_service_range" {
  command = plan
  variables {
    environment = merge(run.staging_defaults.configuration, { network = merge(run.staging_defaults.configuration.network, { services = "10.42.0.0/16", dns_ip = "10.42.0.10" }) })
  }
  expect_failures = [output.configuration]
}

run "dns_outside_services" {
  command = plan
  variables {
    environment = merge(run.staging_defaults.configuration, { network = merge(run.staging_defaults.configuration.network, { dns_ip = "10.45.0.10" }) })
  }
  expect_failures = [output.configuration]
}

run "noncanonical_cidr" {
  command = plan
  variables {
    environment = merge(run.staging_defaults.configuration, { network = merge(run.staging_defaults.configuration.network, { nodes = "10.42.0.1/23" }) })
  }
  expect_failures = [var.environment]
}

run "valid_production_contract" {
  command = plan
  variables {
    # This patch is a syntax fixture, not a verified Azure release selection.
    environment = merge(run.staging_defaults.configuration, {
      name               = "prod"
      classification     = "production"
      registry_private   = true
      postgres_ha        = true
      node_count         = 3
      kubernetes_version = "1.35.6"
      recovery_owner     = "test-operator"
      rpo_minutes        = 60
      rto_minutes        = 240
    })
  }
  assert {
    condition     = output.configuration.classification == "production" && output.configuration.registry_private
    error_message = "A complete production contract must remain valid."
  }
}
