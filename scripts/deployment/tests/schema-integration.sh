#!/usr/bin/env bash
# Run only inside the namespace of a disposable, network-isolated PostgreSQL 17 container.
set -euo pipefail
ROOT=${ROOT:-/repo}
BUILD=${BUILD:-$ROOT/.deployment-local/phase4-bundle/build}
export PGHOST=127.0.0.1 PGUSER=postgres PGPASSWORD=isolated-phase5-only PGDATABASE=postgres
[[ ${PHASE5_ISOLATED_CONTAINER:-} == true ]] || { echo 'Explicit isolated container acknowledgment required' >&2; exit 1; }
ready_deadline=$((SECONDS + 30))
until pg_isready -q; do
  (( SECONDS < ready_deadline )) || { echo 'Fixture database did not become ready' >&2; exit 1; }
  sleep 0.2
done
psql -X -v ON_ERROR_STOP=1 -q -c 'CREATE DATABASE temporal' -c 'CREATE DATABASE temporal_visibility'
credential=$(mktemp)
trap 'rm -f "$credential"' EXIT
printf '%s' "$PGPASSWORD" > "$credential"
chmod 600 "$credential"
export SCHEMA_HOST=127.0.0.1 SCHEMA_PORT=5432 SCHEMA_USER=postgres SCHEMA_PASSWORD_FILE="$credential" SCHEMA_TIMEOUT_SECONDS=120
for db in temporal temporal_visibility; do
  PGDATABASE="$db" psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/deploy/temporal/schemas/roles.sql"
done
for db in temporal temporal_visibility; do
  export PGDATABASE="$db" SCHEMA_DATABASE="$db"
  bash "$ROOT/scripts/deployment/schema.sh" initialize --isolated-test "$BUILD"
  before=$(psql -X -At -c 'SELECT count(*) FROM schema_update_history')
  bash "$ROOT/scripts/deployment/schema.sh" initialize --isolated-test "$BUILD"
  after=$(psql -X -At -c 'SELECT count(*) FROM schema_update_history')
  [[ $before == "$after" ]] || { echo 'Rerun changed migration history' >&2; exit 1; }
  psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/deploy/temporal/schemas/roles.sql"
  psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/deploy/temporal/schemas/roles-test.sql"
  bash "$ROOT/scripts/deployment/schema.sh" verify --isolated-test "$BUILD"
done
echo 'INITIALIZATION_RERUN_AND_ROLE_BOUNDARIES_OK'

# Only these disposable fixture databases are reset to build genuine older schemas.
for db in temporal temporal_visibility; do
  export PGDATABASE="$db" SCHEMA_DATABASE="$db"
  psql -X -q -v ON_ERROR_STOP=1 -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public'
  psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/deploy/temporal/schemas/roles.sql"
  export SQL_HOST=127.0.0.1 SQL_PORT=5432 SQL_USER=postgres SQL_PASSWORD="$PGPASSWORD" SQL_DATABASE="$db" SQL_PLUGIN=postgres12_pgx SQL_TLS=false
  if [[ $db == temporal ]]; then
    kind=temporal; older=1.18; role=temporal_migrator
    insert="INSERT INTO executions(shard_id,namespace_id,workflow_id,run_id,next_event_id,last_write_version,data,data_encoding,state,state_encoding) VALUES(1,decode('01','hex'),'phase5-preserved',decode('02','hex'),2,1,decode('0304','hex'),'proto3',decode('05','hex'),'proto3'); INSERT INTO history_node(shard_id,tree_id,branch_id,node_id,txn_id,data,data_encoding) VALUES(1,decode('01','hex'),decode('02','hex'),1,1,decode('0607','hex'),'proto3')"
    snapshot="SELECT workflow_id||'|'||encode(data,'hex')||'|'||encode(state,'hex') FROM executions ORDER BY workflow_id; SELECT encode(data,'hex') FROM history_node ORDER BY node_id"
  else
    kind=visibility; older=1.13; role=temporal_visibility_migrator
    insert="INSERT INTO executions_visibility(namespace_id,run_id,start_time,execution_time,workflow_id,workflow_type_name,status,encoding,task_queue,memo) VALUES('01','02','2026-01-01','2026-01-01','phase5-preserved','fixture',1,'proto3','fixture',decode('0809','hex'))"
    snapshot="SELECT workflow_id||'|'||encode(memo,'hex') FROM executions_visibility ORDER BY workflow_id"
  fi
  export SQL_CONNECT_ATTRIBUTES="options=-c%20role%3D$role"
  "$BUILD/bin/temporal-sql-tool" setup-schema -v 0.0 >/dev/null 2>&1
  "$BUILD/bin/temporal-sql-tool" update-schema -d "$BUILD/schema/postgresql/v12/$kind/versioned" -v "$older" >/dev/null 2>&1
  psql -X -q -v ON_ERROR_STOP=1 -c "$insert"
  before=$(psql -X -At -v ON_ERROR_STOP=1 -c "$snapshot")
  if bash "$ROOT/scripts/deployment/schema.sh" initialize --isolated-test "$BUILD"; then
    echo 'Older populated initialization was not refused' >&2; exit 1
  fi
  bash "$ROOT/scripts/deployment/schema.sh" upgrade --isolated-test "$BUILD"
  after=$(psql -X -At -v ON_ERROR_STOP=1 -c "$snapshot")
  [[ $before == "$after" ]] || { echo 'Upgrade changed workflow/history/visibility fixture bytes' >&2; exit 1; }
  bash "$ROOT/scripts/deployment/schema.sh" verify --isolated-test "$BUILD"
done
echo 'OLDER_SCHEMA_UPGRADE_PRESERVED_WORKFLOW_HISTORY_AND_VISIBILITY_ROWS_OK'
