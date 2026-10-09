#!/usr/bin/env bash
# Execute inside the disposable PostgreSQL container using its trusted local socket.
set -euo pipefail
[[ ${PHASE5_ISOLATED_CONTAINER:-} == true ]] || exit 1
ROOT=${ROOT:-/repo}
export PGHOST=/var/run/postgresql PGUSER=postgres PGDATABASE=postgres
unset PGOPTIONS PGPASSWORD
psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/deploy/temporal/schemas/roles-login-fixture.sql"
for db in temporal temporal_visibility; do
  if [[ $db == temporal ]]; then
    prefix=temporal; other=temporal_visibility
  else
    prefix=visibility; other=temporal
  fi
  export PGDATABASE="$db"
  PGUSER="nexusflow_test_${prefix}_migrator" PGOPTIONS="-c role=${db}_migrator" psql -X -q -v ON_ERROR_STOP=1 -c 'CREATE TABLE public.nexusflow_login_fixture(id bigserial PRIMARY KEY, value text NOT NULL)'
  psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/deploy/temporal/schemas/roles.sql"
  PGUSER="nexusflow_test_${prefix}_runtime" PGOPTIONS="-c role=${db}_runtime" psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/deploy/temporal/schemas/roles-login-verify.sql"
  if PGDATABASE="$other" PGUSER="nexusflow_test_${prefix}_runtime" PGOPTIONS="-c role=${db}_runtime" psql -X -At -c 'SELECT 1' >/dev/null 2>&1; then
    echo 'Actual runtime LOGIN admitted to the other database' >&2; exit 1
  fi
done
echo 'FOUR_DISTINCT_LOGINS_ADMISSION_AND_PRIVILEGE_BOUNDARIES_OK'
