# Phase 5 implementation evidence

Date: 2026-10-09. Branch: `codex/001-azure-temporal-deployment`. PostgreSQL remains Entra-only. No Azure database roles, schemas, authentication settings, application workloads or resource power states were changed in this phase.

## Implemented

- Database bootstrap defines separate password-free NOLOGIN runtime/migrator roles per store, restricted public privileges, migration ownership/default grants and protected schema audit tables. Entra mapping binds verified service-principal object IDs and tenant to exactly one privilege role, with direct own-store CONNECT and no inherited administrative membership.
- `cmd/tools/entra-token` exchanges a freshly read workload assertion at the fixed Azure public-cloud token endpoint for the PostgreSQL scope. Requests/responses are bounded; expiry must leave five minutes; errors contain no assertions or tokens. Per-store `--client-id` UUID selection supports two runtime identities in the same Temporal process. No new Go dependency was introduced.
- Inspection found the fork already rebuilds DSNs through `passwordCommand` on each new physical PostgreSQL connection, including baseline 717f. The new helper reuses that hook; the connection driver did not need a new token cache or background refresh loop. Existing pooled connections are not forcibly reauthenticated.
- Explicit schema operations validate matching source artifacts and release evidence, verify full database TLS, select migration ownership, hold a persistent advisory lock and retain a private pending intent if DDL fails. Initialization reruns verify; upgrades require an explicit older compatible baseline. Production obtains a fresh qualified helper token before guard/command connections; only isolated loopback fixtures accept a password file.
- Six suspended schema Jobs cover both stores and three operations. They use distinct migration service accounts, projected Entra assertions, nonsecret identity references, read-only CA, no static passwords, no default Kubernetes API token, no retry, deadlines and hardened pods. The pinned standard-OS executor packaging includes the source-built tools and guarded wrapper.
- The schema runbook records backup/restore prerequisites, serial ordering, partial-failure assessment and schema rollback restrictions. Credential-free CI now covers helper/refresh-hook tests and the new schema assets.
- Web UI is in hosting scope. The user created `amitkohad/temporal-ui`; API verification confirms official parent `temporalio/ui` and candidate source HEAD `7a54e4ae74e699766464fe67250e27b4d0344253`. Feature/spec/plan/contracts and tasks now cover its separate source build, private hosting, HTTPS/OIDC, frontend authorization and readiness tests.

## Verification

Real PostgreSQL 17.11 tests used official test-only image digest `sha256:3645570cccdfa447589da9f57dd740faa29b30938e861289a5574b6ca6b03826`, a dedicated `--network none` container, shared loopback network namespace and tmpfs data. No port was published and no Azure credential entered the fixture.

| Check | Result |
|---|---|
| All deployment Python helper tests | 56 passed |
| Go tests with `-tags test_dep`: Entra helper, SQL refreshing connector, config | Passed |
| `go vet -tags test_dep ./cmd/tools/entra-token` | Passed |
| Bash syntax of schema wrapper/integration scripts | Passed |
| Both empty schemas initialized, repeated initialization unchanged migration history | Passed: persistence 1.19, visibility 1.14 |
| Genuine upgrades 1.18 to 1.19 and 1.13 to 1.14 | Passed; fixture workflow/history/visibility bytes preserved |
| Real runtime/migration LOGIN identities and privilege boundaries | Passed: DML allowed, DDL/audit writes/escalation/cross-store connections denied |
| Real advisory contention and pending/newer/wrong-store refusals | Four checks passed; fixture state restored |
| Verified TLS plus invalid CA/hostname with psql and fork-built SQL tool | Passed |
| Required `make lint-code-fast` and scoped pinned golangci-lint | Not passed: pinned linter cannot read Go 1.27 export data (version 5, supported maximum 4); initial broad loader timed out after CRLF made packages appear changed. No formatter changes were retained. Track T104. |

The preserved rows are representative storage fixtures, not an end-to-end Temporal workflow execution. Unit tests model fresh token acquisition/expiry; real Azure federation, expiring Entra credentials, concurrent pool reconnects and certificate-chain validation remain T096/T085 execution evidence.

## Remaining gates

T045 is partial until the new executor is source-qualified and runnable by immutable digest. T095 must extend the build/publisher/evidence contract and package the helper into the runtime image. The old immutable server source baseline lacks the new helper; a reviewed commit containing it is required. Do not fabricate release evidence by appending a local helper to the frozen Phase 4 bundle.

The existing Phase 4 unclassified scanner findings still prevent accepted publication. GitHub publisher federation, runtime/migration identity provisioning and actual PostgreSQL principal mapping remain pending. Jobs remain suspended and no cloud schema/rollout occurred. T047's runbook is written; operator ownership and restore acceptance remain review gates. T104 tracks the lint/toolchain issue. Phase 6 contains the server configuration and Web UI build/hosting work; inclusion in scope does not mean the UI is already hosted.
