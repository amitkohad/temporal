# PostgreSQL schema operations

Use explicit `initialize`, `upgrade`, or `verify` operations before starting Temporal. The selected fork currently requires PostgreSQL persistence 1.19 and visibility 1.14. Run one database at a time; never run migrations from server startup or Helm hooks. The source-built SQL tool uses its matching versioned schema directories. Do not use overwrite, drop-database, or the tool's dry-run mode: its dry-run path can create a database.

## Prerequisites

The database operator confirms the release manifest, source commit, schemas, accepted scan evidence and immutable executor digest. Phase 4 findings still block publication. The release contract must qualify the new `entra-token` auxiliary binary and migration executor before production operations can run. Suspended Job templates are preparation artifacts, not runnable releases.

Keep Azure PostgreSQL Entra-only. Create four independent workload identities for persistence runtime, visibility runtime and the two migrators. Bind identities through Azure overrides, map service-principal object IDs using `entra-principal.sql` from the `postgres` database as the Entra administrator, and grant only the corresponding NOLOGIN role. Run `roles.sql` separately in both dedicated databases as administrator. Runtime users can manipulate application data; they cannot own schemas, create temporary objects, change schema versions or assume migration roles. Reapply grants after migrations so schema audit tables are read-only for runtime.

Mount the actual PostgreSQL trust bundle and use the certificate FQDN for `SCHEMA_HOST`. Resolve that FQDN privately. Do not substitute a private IP or disable hostname verification. Keep tokens, assertions and SQL output out of logs and Terraform state. Runtime password commands request a fresh Entra token for every physical connection; migration commands request a fresh token before each bounded command. No password fallback is enabled in Azure.

Before upgrading a populated database, record backup/PITR availability, recovery owner, restore destination, last known-good server/schema pair and a successful isolated restore rehearsal. Record a recovery checkpoint for both databases; a configured seven-day retention policy alone is not restore evidence. Empty initial databases need a documented emptiness check and no preexisting workflows. This phase creates no Azure schema or role changes.

## Execute and verify

On the private runner or qualified executor, supply `SCHEMA_HOST`, `SCHEMA_PORT`, `SCHEMA_DATABASE`, `SCHEMA_USER`, `SCHEMA_CA_FILE`, workload identity environment and `SCHEMA_TIMEOUT_SECONDS`. Use `temporal` or `temporal_visibility`; usernames are mapped Entra principals rather than NOLOGIN role names. Run:

```bash
bash scripts/deployment/schema.sh verify /private/release/published-manifest.json
bash scripts/deployment/schema.sh initialize /private/release/published-manifest.json
# Use upgrade only after reviewing an existing older baseline and its full path.
bash scripts/deployment/schema.sh upgrade /private/release/published-manifest.json
```

Select the needed operation explicitly. Verification refuses empty stores; initialization refuses older populated stores and becomes verification on an already current store. Upgrades refuse newer schemas, wrong store markers, inconsistent compatibility metadata and missing version paths. Each operation holds a persistent PostgreSQL advisory lock and checks that connection throughout execution. The private `nexusflow_migration.intent` table records pending state before DDL. A successful final version check completes the intent. Concurrent operations are denied; command failure, deadline or guard loss stops execution without automatic retry.

Initialize or upgrade both stores serially, reapply `roles.sql`, then verify exact versions and runtime DML/DDL denial before rollout. Store sanitized operation results with database, source revision, schema versions, operator and backup reference. Do not publish access tokens, usernames' credential material or raw SQL errors.

## Interrupted operation and rollback

Stop rollout and preserve the pending intent. Inspect the source migration chain, applied objects and `schema_update_history` using administrator access. Temporal schema DDL is not one atomic transaction; a failed tool may have applied part of a step. Do not clear the intent or rerun blindly. The database owner must determine a reviewed repair or isolated restore path, document it, and verify the database before explicitly clearing a pending record. Verification never repairs data.

Server rollback is allowed only when its documented minimum schema compatibility supports the resulting database. Do not downgrade schemas or erase newer objects to make an older binary start. Otherwise restore both stores to the agreed checkpoint in isolated resources, validate workflow continuity, and switch endpoints through a separately reviewed recovery operation.

## Isolated checks

`scripts/deployment/tests/schema-integration.sh` runs only with `PHASE5_ISOLATED_CONTAINER=true`, inside a disposable PostgreSQL container's network namespace. It uses loopback, an explicit test-only password, no published port and ephemeral storage. `--isolated-test` cannot be used for Azure hostnames and does not qualify a production release. The test validates real source-built schema operations and privilege boundaries; Azure Entra exchange, workload federation and restore rehearsal need separate live evidence.
