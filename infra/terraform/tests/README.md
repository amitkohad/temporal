# Phase 2 test catalogue

Terraform 1.10 requires tests to reside inside each configuration directory. The tests are indexed here and run through [the non-deploying validation script](../../../scripts/deployment/validate-terraform.ps1).

| Suite | Coverage |
|---|---|
| [Contracts](../modules/contracts/tests/configuration.tftest.hcl) | Immutable source, production gates, exact version syntax, network boundaries and overlapping CIDRs |
| [Resource group](../modules/azure/resource-group/tests/ownership.tftest.hcl) | Existing shared group owns no resource, explicit create owns one, unrelated names rejected |
| [Environment](../environments/azure/tests/scope.tftest.hcl) | Explicit Azure scope, existing/create selection, distinct state keys, malformed scope rejected |
| [Bootstrap](../bootstrap/azure/tests/state.tftest.hcl) | Private state, Entra-only access, version/deletion retention, optional branch-bound federation, scoped permissions and invalid inputs |

All runs use command=plan. AzureRM and AzAPI providers are mocked; no Azure credentials are needed and no backend is initialized. Terraform test plans are simulated inside the test harness, not live Azure plans.
Mocks verify declared contracts and policies, not Azure RBAC effectiveness, real OIDC tokens, DNS connectivity, private endpoint provisioning or restore behavior. Those remain later authorized staging checks.
Provider packages must be downloaded once; offline tests can then reuse the local .terraform directory. Module/provider downloads are not Azure provisioning.
