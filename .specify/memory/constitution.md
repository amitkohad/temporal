# Temporal Deployment Constitution

Version: 1.0.0 | Adopted: 2026-10-09

This constitution governs deployment features and supplements AGENTS.md and .github/copilot-instructions.md; it does not replace server development rules.

1. Specify before implementing. Record user outcomes, acceptance scenarios, decisions, contracts, and traceable tasks. Unresolved infrastructure inputs must be resolved before execution.
2. Build Temporal artifacts from the approved commit of https://github.com/amitkohad/temporal. Use matching server, SQL tools, and schemas. Do not substitute published Temporal images or download application binaries.
3. Preserve portability through explicit boundaries. Azure resources require Azure-specific Terraform providers. Keep those resources in Azure adapters; keep Temporal configuration and Kubernetes deployment portable. Do not claim unimplemented cloud adapters exist.
4. Keep private systems private. Use least-privilege identities, private database and service access, encrypted connections, protected state, and auditable secret rotation.
5. Protect durable state. Schema changes are explicit, serialized operations. Prohibit destructive initialization against existing databases. Prove backup recovery and compatibility before upgrades.
6. Separate build, provisioning, schema migration, and application rollout. Default validation is non-deploying. No cloud mutation or deployment is authorized by these planning artifacts.
7. Verify meaningful behavior. Static checks cover Terraform, rendered Kubernetes resources, workflows, and source provenance; later staging checks cover durable execution, visibility, failover, upgrades, and recovery. Follow docs/development/testing.md and use test_dep for Go tests.
8. Prefer existing repository patterns and minimal changes. Document deviations and operational tradeoffs; choose capacity from measured workloads rather than arbitrary replica counts.
