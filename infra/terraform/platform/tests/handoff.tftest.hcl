variables {
  handoff = {
    environment             = "stg"
    source_commit           = "717f485c760d1068aa310906466468e51120254f"
    private_access_verified = true
    kubernetes              = { name = "aks-nexusflow-stg-ci", private_fqdn = "example.private.azure.test", oidc_issuer = "https://example.test/issuer" }
    registry                = { hostname = "example.azurecr.test" }
    persistence             = { hostname = "example.postgres.test", port = 5432, database = "temporal", visibility_database = "temporal_visibility", tls_required = true }
    secret_store            = { uri = "https://example.vault.test/" }
  }
}
run "verified_nonsecret_handoff" {
  command = plan
  assert {
    condition     = output.deployment_contract.persistence.database != output.deployment_contract.persistence.visibility_database
    error_message = "Runtime handoff must preserve separate database references."
  }
}
run "unverified_private_path" {
  command = plan
  variables { handoff = merge(run.verified_nonsecret_handoff.deployment_contract, { private_access_verified = false }) }
  expect_failures = [var.handoff]
}
run "plaintext_database" {
  command = plan
  variables { handoff = merge(run.verified_nonsecret_handoff.deployment_contract, { persistence = merge(run.verified_nonsecret_handoff.deployment_contract.persistence, { tls_required = false }) }) }
  expect_failures = [var.handoff]
}