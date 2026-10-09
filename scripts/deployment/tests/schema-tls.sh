#!/usr/bin/env bash
# Fixture certificates and PostgreSQL belong to a disposable, network-isolated container.
set -euo pipefail
[[ ${PHASE5_ISOLATED_CONTAINER:-} == true ]] || exit 1
ROOT=${ROOT:-/repo}
BUILD=${BUILD:-$ROOT/.deployment-local/phase4-bundle/build}
export PGHOST=localhost PGUSER=postgres PGPASSWORD=isolated-phase5-only PGDATABASE=temporal
export PGSSLMODE=verify-full PGSSLROOTCERT="$ROOT/.deployment-local/phase5-tls/ca.crt"
psql -X -At -v ON_ERROR_STOP=1 -c 'SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()' | grep -qx t
if PGSSLROOTCERT="$ROOT/.deployment-local/phase5-tls/wrong-ca.crt" psql -X -At -c 'SELECT 1' >/dev/null 2>&1; then
  echo 'Wrong CA accepted' >&2; exit 1
fi
if PGHOST=127.0.0.1 psql -X -At -c 'SELECT 1' >/dev/null 2>&1; then
  echo 'Wrong hostname accepted' >&2; exit 1
fi
export SQL_HOST=localhost SQL_PORT=5432 SQL_USER=postgres SQL_PASSWORD="$PGPASSWORD" SQL_DATABASE=temporal SQL_PLUGIN=postgres12_pgx SQL_TLS=true SQL_TLS_CA_FILE="$PGSSLROOTCERT" SQL_TLS_DISABLE_HOST_VERIFICATION=false
command=("$BUILD/bin/temporal-sql-tool" update-schema -d "$BUILD/schema/postgresql/v12/temporal/versioned" -v 1.19)
"${command[@]}" >/dev/null 2>&1
if SQL_TLS_CA_FILE="$ROOT/.deployment-local/phase5-tls/wrong-ca.crt" "${command[@]}" >/dev/null 2>&1; then
  echo 'Source-built SQL tool accepted wrong CA' >&2; exit 1
fi
if SQL_HOST=127.0.0.1 "${command[@]}" >/dev/null 2>&1; then
  echo 'Source-built SQL tool accepted wrong hostname' >&2; exit 1
fi
echo 'TLS_VERIFIED_AND_INVALID_CA_HOSTNAME_REJECTED_BY_PSQL_AND_FORK_SQL_TOOL'
