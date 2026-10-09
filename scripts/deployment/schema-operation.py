#!/usr/bin/env python3
"""Bounded, fail-closed Temporal PostgreSQL schema operations."""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time
import urllib.parse
import uuid

PAIRS = {"temporal": ("temporal", "persistence", "temporal_migrator"),
         "temporal_visibility": ("visibility", "visibility", "temporal_visibility_migrator")}
LOCK_KEY = 6374820192571


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9]+\.[0-9]+", value), "Invalid schema version")
    return tuple(map(int, value.split(".")))


def decision(operation, current, target, compatible, expected_minimum, markers_ok):
    if current is None:
        require(operation == "initialize", "Empty database requires explicit initialize")
        return "initialize"
    require(markers_ok, "Database schema type does not match selected store")
    require(version(current) <= version(target), "Database is newer than the source release")
    require(compatible == expected_minimum, "Schema compatibility metadata mismatch")
    if current == target:
        return "verify"
    require(operation == "upgrade", "Older database requires explicit upgrade")
    return "upgrade"


def hash_file(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_contract(path, isolated):
    if isolated:
        root = path.resolve()
        metadata = json.loads((root / "build-metadata.json").read_text())
        require(metadata.get("source_dirty") is False and metadata.get("source_repository") == "https://github.com/amitkohad/temporal", "Isolated test requires clean fork source artifacts")
        require(metadata.get("platform") == "linux/amd64" and re.fullmatch(r"[0-9a-f]{40}", metadata.get("source_commit", "")), "Invalid isolated source metadata")
        for name, expected in metadata["files"].items():
            resolved = (root / name).resolve()
            require(resolved.is_relative_to(root) and resolved.is_file() and hash_file(resolved) == expected, "Source artifact checksum mismatch")
        binary = root / "bin/temporal-sql-tool"
        require("bin/temporal-sql-tool" in metadata["files"], "Source-built SQL tool missing")
        schemas = root / "schema/postgresql/v12"
        return binary, schemas, metadata["schema_versions"]
    spec = importlib.util.spec_from_file_location("release_evidence", Path(__file__).with_name("release-evidence.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    manifest = module.validate(json.loads(path.read_text()), path.parent, published=True)
    binary = path.parent / manifest["binaries"]["temporal-sql-tool"]["path"]
    metadata_path = path.parent / manifest["build_metadata"]["path"]
    return binary, metadata_path.parent / "schema/postgresql/v12", {
        "persistence": manifest["schemas"]["persistence_version"], "visibility": manifest["schemas"]["visibility_version"]}


class Guard:
    def __init__(self, environment, deadline):
        self.deadline = deadline
        self.rows = queue.Queue()
        self.process = subprocess.Popen(["psql", "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1"],
                                        env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def read(self):
        for line in self.process.stdout:
            self.rows.put(line.rstrip("\r\n"))
        self.rows.put(None)

    def query(self, sql):
        require(self.process.poll() is None, "Migration guard connection was lost; stop and review")
        marker = "GUARD_" + uuid.uuid4().hex
        self.process.stdin.write(sql + ";\n\\echo " + marker + "\n")
        self.process.stdin.flush()
        result = []
        expires = min(self.deadline, time.monotonic() + 10)
        while True:
            remaining = expires - time.monotonic()
            require(remaining > 0, "Migration guard timed out; stop and review")
            try:
                row = self.rows.get(timeout=remaining)
            except queue.Empty:
                raise ValueError("Migration guard timed out; stop and review") from None
            require(row is not None, "Migration guard query failed; stop and review")
            if row == marker:
                return result
            if row:
                result.append(row)

    def close(self):
        if self.process.poll() is None:
            try:
                self.process.stdin.write("\\q\n")
                self.process.stdin.flush()
                self.process.wait(timeout=3)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                self.process.kill()
                self.process.wait()
        self.process.stdin.close()
        self.process.stdout.close()


def run_tool(binary, command, environment, guard, deadline):
    child = subprocess.Popen([str(binary), *command], env=environment,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        while child.poll() is None:
            require(time.monotonic() < deadline, "Schema command deadline exceeded; retain pending intent")
            guard.query("SELECT 1")
            try:
                child.wait(timeout=min(2, max(0.1, deadline - time.monotonic())))
            except subprocess.TimeoutExpired:
                pass
        require(child.returncode == 0, "Schema tool failed; retain pending intent and review before retry")
        guard.query("SELECT 1")
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()


def manifests(schema, target):
    result = {}
    for directory in (schema / "versioned").iterdir():
        if directory.is_dir() and re.fullmatch(r"v[0-9]+\.[0-9]+", directory.name):
            manifest = json.loads((directory / "manifest.json").read_text())
            value = directory.name[1:]
            require(manifest["CurrVersion"] == value and version(manifest["MinCompatibleVersion"]) <= version(value), "Invalid source upgrade manifest")
            for filename in manifest["SchemaUpdateCqlFiles"]:
                require((directory / filename).resolve().is_relative_to(directory.resolve()) and (directory / filename).is_file(), "Upgrade SQL file missing or unsafe")
            result[value] = manifest
    require(target in result, "Target upgrade schema missing")
    return result


def renewable_auth(environment, helper, minimum_lifetime):
    if helper is None:
        return dict(environment)
    executable, expected_hash = helper
    require(hash_file(executable) == expected_hash, "Qualified token helper changed")
    try:
        response = subprocess.run([str(executable)], env=environment, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, timeout=30, check=True)
    except subprocess.SubprocessError:
        raise ValueError("Entra token acquisition failed; token output suppressed") from None
    token = response.stdout.strip()
    require(token and '\n' not in token and '\r' not in token, "Token helper returned invalid output")
    try:
        payload = token.split('.')[1]
        claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        expiry = int(claims['exp'])
    except (ValueError, IndexError, KeyError, TypeError):
        raise ValueError("Token helper must return an expiring PostgreSQL access token") from None
    require(expiry >= time.time() + minimum_lifetime + 60, "Fresh token lifetime is too short for bounded command")
    renewed = dict(environment)
    renewed.update(PGPASSWORD=token, SQL_PASSWORD=token)
    return renewed


def qualified_helper(path):
    manifest = json.loads(path.read_text())
    item = manifest.get('auxiliary_binaries', {}).get('entra-token')
    require(isinstance(item, dict) and item.get('source_commit') == manifest['source']['commit'], "Published release must qualify the source-built Entra token helper")
    bundled = (path.parent / item['path']).resolve()
    require(bundled.is_relative_to(path.parent.resolve()) and bundled.is_file() and hash_file(bundled) == item['sha256'], "Qualified Entra helper artifact mismatch")
    configured = Path(os.environ.get('SCHEMA_TOKEN_HELPER', str(bundled))).resolve()
    require(configured.is_file() and hash_file(configured) == item['sha256'], "Configured Entra helper differs from qualified artifact")
    return configured, item['sha256']


def connection(isolated, database):
    host = os.environ.get("SCHEMA_HOST", "")
    require(host and not any(c.isspace() for c in host), "SCHEMA_HOST required")
    require(not isolated or host in ("127.0.0.1", "localhost", "::1"), "Isolated test may connect only to loopback PostgreSQL")
    port = os.environ.get("SCHEMA_PORT", "5432")
    require(port.isdigit() and 1 <= int(port) <= 65535, "Invalid schema port")
    user = os.environ.get("SCHEMA_USER", "")
    require(user, "SCHEMA_USER required")
    role = PAIRS[database][2]
    timeout = int(os.environ.get("SCHEMA_TIMEOUT_SECONDS", "900"))
    require(30 <= timeout <= 3600, "Schema timeout must be between 30 and 3600 seconds")
    environment = {k: v for k, v in os.environ.items() if not k.startswith(("SQL_", "PG")) and k not in ('SCHEMA_PASSWORD_FILE', 'AZURE_CLIENT_SECRET')}
    options = "-c role=" + role + " -c search_path=public -c statement_timeout=" + str(min(timeout, 600) * 1000) + " -c idle_session_timeout=0"
    environment.update(PGHOST=host, PGPORT=port, PGDATABASE=database, PGUSER=user,
                       PGCONNECT_TIMEOUT="10", PGOPTIONS=options, SQL_HOST=host, SQL_PORT=port,
                       SQL_DATABASE=database, SQL_USER=user, SQL_PLUGIN="postgres12_pgx",
                       SQL_CONNECT_ATTRIBUTES=urllib.parse.urlencode({"options": options}),
                       SQL_TLS_DISABLE_HOST_VERIFICATION="false")
    if isolated:
        credential = Path(os.environ["SCHEMA_PASSWORD_FILE"])
        require(credential.is_file() and not credential.is_symlink(), "Credential file missing or unsafe")
        if os.name == "posix":
            require(credential.stat().st_mode & 0o077 == 0, "Credential file must restrict group and other access")
        password = credential.read_text().rstrip("\r\n")
        require(password, "Credential file is empty")
        environment.update(PGSSLMODE="disable", SQL_TLS="false", PGPASSWORD=password, SQL_PASSWORD=password)
    else:
        require(not os.environ.get('SCHEMA_PASSWORD_FILE') and not os.environ.get('AZURE_CLIENT_SECRET'), "Production schema operations require Entra workload identity, not static secrets")
        ca = Path(os.environ.get("SCHEMA_CA_FILE", ""))
        require(ca.is_file(), "Trusted PostgreSQL CA file required")
        environment.update(PGSSLMODE="verify-full", PGSSLROOTCERT=str(ca), SQL_TLS="true",
                           SQL_TLS_CA_FILE=str(ca), SQL_TLS_SERVER_NAME=host)
    return environment, time.monotonic() + timeout

def execute(operation, path, isolated):
    database = os.environ.get("SCHEMA_DATABASE", "")
    require(database in PAIRS, "Select temporal or temporal_visibility database")
    kind, key, role = PAIRS[database]
    binary, schemas, versions = build_contract(path, isolated)
    target = versions[key]
    require(versions == {"persistence": "1.19", "visibility": "1.14"}, "This decision record requires PostgreSQL schemas 1.19/1.14")
    available = manifests(schemas / kind, target)
    environment, deadline = connection(isolated, database)
    helper = None if isolated else qualified_helper(path)
    guard = Guard(renewable_auth(environment, helper, 30), deadline)
    try:
        require(guard.query("SELECT pg_try_advisory_lock(" + str(LOCK_KEY) + ")") == ["t"], "Concurrent migration denied")
        require(guard.query("SELECT to_regnamespace('nexusflow_migration') IS NOT NULL") == ["t"], "Prepare private migration-intent schema using roles.sql first")
        exists = guard.query("SELECT to_regclass('nexusflow_migration.intent') IS NOT NULL") == ["t"]
        if exists:
            require(guard.query("SELECT count(*) FROM nexusflow_migration.intent WHERE status='pending'") == ["0"], "Unresolved prior migration intent; inspect partial DDL before retry")
        objects = guard.query("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','S')")[0]
        current = compatible = None
        markers_ok = False
        if objects != "0":
            require(guard.query("SELECT to_regclass('public.schema_version') IS NOT NULL") == ["t"], "Nonempty unversioned database refused")
            rows = guard.query("SELECT curr_version || '|' || min_compatible_version FROM public.schema_version WHERE version_partition=0 AND db_name=current_database()")
            require(len(rows) == 1 and len(rows[0].split('|')) == 2, "Ambiguous or missing schema-version row")
            current, compatible = rows[0].split('|')
            if kind == "temporal":
                markers_ok = guard.query("SELECT to_regclass('public.executions') IS NOT NULL AND to_regclass('public.namespaces') IS NOT NULL AND to_regclass('public.executions_visibility') IS NULL") == ["t"]
            else:
                markers_ok = guard.query("SELECT to_regclass('public.executions_visibility') IS NOT NULL AND to_regclass('public.namespaces') IS NULL") == ["t"]
        expected_minimum = available.get(current or target, {}).get("MinCompatibleVersion")
        action = decision(operation, current, target, compatible, expected_minimum, markers_ok)
        if action == "upgrade":
            require(current in available, "Source release does not contain the current upgrade baseline")
            require(version(current)[0] == version(target)[0], "Cross-major schema upgrades require a separate reviewed plan")
            require(all(str(version(current)[0]) + '.' + str(minor) in available for minor in range(version(current)[1] + 1, version(target)[1] + 1)), "Upgrade path has an unsupported gap")
        if action != "verify":
            guard.query("CREATE TABLE IF NOT EXISTS nexusflow_migration.intent (id integer PRIMARY KEY CHECK(id=1), status text NOT NULL CHECK(status IN ('pending','completed')), source_version text, target_version text NOT NULL)")
            guard.query("INSERT INTO nexusflow_migration.intent VALUES (1,'pending','" + (current or "empty") + "','" + target + "') ON CONFLICT(id) DO UPDATE SET status='pending',source_version=excluded.source_version,target_version=excluded.target_version")
            if action == "initialize":
                run_tool(binary, ["setup-schema", "-v", "0.0"], renewable_auth(environment, helper, min(600, max(30, deadline - time.monotonic()))), guard, min(deadline, time.monotonic() + 600))
            run_tool(binary, ["update-schema", "-d", str(schemas / kind / "versioned"), "-v", target], renewable_auth(environment, helper, min(600, max(30, deadline - time.monotonic()))), guard, min(deadline, time.monotonic() + 600))
        rows = guard.query("SELECT curr_version || '|' || min_compatible_version FROM public.schema_version WHERE version_partition=0 AND db_name=current_database()")
        require(rows == [target + '|' + available[target]['MinCompatibleVersion']], "Final schema verification failed; retain pending intent")
        if action != "verify":
            guard.query("UPDATE nexusflow_migration.intent SET status='completed' WHERE id=1")
        print("SCHEMA_OK database=" + database + " version=" + target + " action=" + action)
    finally:
        guard.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("initialize", "upgrade", "verify"))
    parser.add_argument("release", nargs="?", type=Path)
    parser.add_argument("--isolated-test", type=Path, metavar="BUILD_DIRECTORY")
    args = parser.parse_args()
    try:
        require((args.release is not None) != (args.isolated_test is not None), "Provide accepted published manifest or explicit isolated-test build directory")
        execute(args.operation, args.release or args.isolated_test, args.isolated_test is not None)
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        # Connection errors and SQL-tool output are deliberately not echoed.
        print("SCHEMA_REFUSED " + (str(error) if isinstance(error, ValueError) else "Execution failed; retain pending intent and review"), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())