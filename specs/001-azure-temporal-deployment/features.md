# Feature catalogue: Source-built Temporal on Azure

Branch: codex/001-azure-temporal-deployment
Status: Infrastructure and source-build phases implemented; Phase 5 validated locally with execution/lint gates outstanding; runtime and UI hosting pending
Resource group: rg-nexusflow
Source repository: https://github.com/amitkohad/temporal

| Feature | Outcome | Story | Requirements |
|---|---|---|---|
| F01 Infrastructure foundation | Bootstrap state and a new AKS/ACR/PostgreSQL environment | US1 | FR-001–FR-005, FR-011 |
| F02 Portable deployment boundary | Azure adapters expose stable contracts to shared Kubernetes configuration | US1 | FR-006 |
| F03 Source build and provenance | Server and SQL-tool images originate from one approved commit | US2 | FR-007–FR-010 |
| F04 Safe PostgreSQL lifecycle | Initialize and upgrade both stores without deleting data | US3 | FR-012–FR-014 |
| F05 Private resilient Temporal | Run four services with private access, TLS, and supported availability settings | US3 | FR-015–FR-019 |
| F06 Operational readiness | Monitor, load-test, restore, and maintain the service | US4 | FR-020–FR-023 |
| F07 Controlled delivery | Separate validation from future cloud execution | US1–US4 | FR-024–FR-026 |

Hosting scope includes Temporal Server, its internal worker, SQL schema tools, renewable Entra credential helper, migration executor, and Temporal Web UI. UI source comes from the user-approved fork https://github.com/amitkohad/temporal-ui; deployment implementation stays on codex/001-azure-temporal-deployment. Production application workers remain outside scope.

Additional hosting features:

| Feature | Outcome | Story | Requirements |
|---|---|---|---|
| F08 Private source-built Web UI | Browser access to approved namespaces through private HTTPS/OIDC | US3 | FR-015, FR-027 |
| F09 Renewable database identity | Entra token renewal per connection without stored passwords | US3 | FR-014, FR-028 |
