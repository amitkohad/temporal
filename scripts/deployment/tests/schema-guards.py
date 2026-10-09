#!/usr/bin/env python3
"""Optional, destructive isolated-fixture checks; never run against Azure."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import time


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    require(os.environ.get('PHASE5_ISOLATED_CONTAINER') == 'true', 'Explicit isolated-container authorization required')
    require(Path('/.dockerenv').is_file(), 'Run only inside the isolated PostgreSQL fixture container network')
    require(os.environ.get('SCHEMA_HOST') in ('127.0.0.1', 'localhost', '::1'), 'Only loopback PostgreSQL permitted')
    require(os.environ.get('SCHEMA_DATABASE') == 'temporal', 'This fixture requires temporal database')
    root = Path(os.environ.get('ROOT', '/repo')).resolve()
    build = Path(os.environ['BUILD']).resolve()
    operation = root / 'scripts/deployment/schema-operation.py'
    require(operation.is_file() and (build / 'build-metadata.json').is_file(), 'Fixture driver and compiled artifacts required')
    spec = importlib.util.spec_from_file_location('isolated_schema_operation', operation)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    environment, _ = module.connection(True, 'temporal')
    guard = module.Guard(environment, time.monotonic() + 900)
    checks = []

    def refused(reason):
        try:
            result = subprocess.run([sys.executable, str(operation), 'verify', '--isolated-test', str(build)],
                                    env=dict(os.environ), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    text=True, timeout=300)
        except subprocess.TimeoutExpired:
            raise RuntimeError('Fixture schema check timed out; inspect state before retry') from None
        # Do not print arbitrary command output; assert only the known redacted reason.
        require(result.returncode != 0 and reason in result.stderr and 'SCHEMA_OK' not in result.stdout,
                'Expected guarded refusal was not observed: ' + reason)
        checks.append(reason)
        print('FIXTURE_GUARD_OK ' + reason, flush=True)

    try:
        rows = guard.query("SELECT curr_version || '|' || min_compatible_version FROM public.schema_version WHERE version_partition=0 AND db_name=current_database()")
        require(rows == ['1.19|1.0'], 'Initialize or upgrade the isolated fixture to 1.19 first')
        require(guard.query("SELECT status FROM nexusflow_migration.intent WHERE id=1") == ['completed'], 'A completed fixture migration intent is required')
        require(guard.query("SELECT to_regclass('public.namespaces_guard_fixture') IS NULL") == ['t'], 'Fixture rename destination already exists')
        require(guard.query('SELECT pg_try_advisory_lock(' + str(module.LOCK_KEY) + ')') == ['t'], 'Fixture migration lease is already held')
        try:
            refused('Concurrent migration denied')
        finally:
            guard.query('SELECT pg_advisory_unlock(' + str(module.LOCK_KEY) + ')')

        guard.query("UPDATE nexusflow_migration.intent SET status='pending' WHERE id=1")
        try:
            refused('Unresolved prior migration intent')
        finally:
            guard.query("UPDATE nexusflow_migration.intent SET status='completed' WHERE id=1")

        guard.query("UPDATE public.schema_version SET curr_version='1.20' WHERE version_partition=0 AND db_name=current_database()")
        try:
            refused('Database is newer than the source release')
        finally:
            guard.query("UPDATE public.schema_version SET curr_version='1.19' WHERE version_partition=0 AND db_name=current_database()")

        guard.query('ALTER TABLE public.namespaces RENAME TO namespaces_guard_fixture')
        try:
            refused('Database schema type does not match selected store')
        finally:
            guard.query('ALTER TABLE public.namespaces_guard_fixture RENAME TO namespaces')

        require(guard.query("SELECT curr_version || '|' || min_compatible_version FROM public.schema_version WHERE version_partition=0 AND db_name=current_database()") == ['1.19|1.0'], 'Fixture version was not restored')
        require(guard.query("SELECT status FROM nexusflow_migration.intent WHERE id=1") == ['completed'], 'Fixture migration intent was not restored')
        require(guard.query("SELECT to_regclass('public.namespaces') IS NOT NULL AND to_regclass('public.namespaces_guard_fixture') IS NULL") == ['t'], 'Fixture table was not restored')
    finally:
        guard.close()
    print('FIXTURE_GUARDS_OK checks=' + str(len(checks)))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError):
        print('FIXTURE_GUARDS_FAILED inspect isolated fixture; details suppressed', file=sys.stderr)
        sys.exit(1)