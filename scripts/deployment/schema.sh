#!/usr/bin/env bash
# Execute guarded migration from a private operator runner, never server startup.
set -euo pipefail
exec python3 "$(dirname "$0")/schema-operation.py" "$@"