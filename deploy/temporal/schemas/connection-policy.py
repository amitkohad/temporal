#!/usr/bin/env python3
"""Reject PostgreSQL schema-tool connection settings that weaken TLS or roles."""
import argparse
import ipaddress
import os
import re
import sys
from pathlib import Path
from urllib.parse import parse_qs


def validate(environment, operation="migration", allow_local_test=False):
    host = environment.get("SQL_HOST", "")
    if not host or re.search(r"[\s/:@]", host):
        raise ValueError("SQL_HOST must be a DNS hostname, without a URL or port")
    try:
        ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        if not allow_local_test:
            raise ValueError("Use the certificate DNS hostname rather than an IP")
    if not allow_local_test and ("." not in host or host == "localhost"):
        raise ValueError("Use the verified database FQDN")
    database = environment.get("SQL_DATABASE")
    if database not in ("temporal", "temporal_visibility"):
        raise ValueError("Only the two dedicated Temporal databases are allowed")
    suffix = "migrator" if operation == "migration" else "runtime"
    role = database + "_" + suffix
    if environment.get("SQL_PLUGIN") not in ("postgres12", "postgres12_pgx"):
        raise ValueError("Select the repository PostgreSQL plugin")
    if environment.get("SQL_TLS", "").lower() != "true":
        raise ValueError("SQL_TLS=true is required")
    if environment.get("SQL_TLS_DISABLE_HOST_VERIFICATION", "false").lower() != "false":
        raise ValueError("TLS hostname verification must remain enabled")
    if environment.get("SQL_TLS_SERVER_NAME", host) != host:
        raise ValueError("SQL_TLS_SERVER_NAME must equal SQL_HOST")
    ca = Path(environment.get("SQL_TLS_CA_FILE", ""))
    if not ca.is_file() or "-----BEGIN CERTIFICATE-----" not in ca.read_text():
        raise ValueError("A mounted trusted PEM CA bundle is required")
    attributes = parse_qs(environment.get("SQL_CONNECT_ATTRIBUTES", ""), keep_blank_values=True, strict_parsing=True)
    if set(attributes) - {"options", "connect_timeout", "application_name"}:
        raise ValueError("Connection attributes must not override TLS or add unreviewed settings")
    if any(len(values) != 1 for values in attributes.values()):
        raise ValueError("Duplicate connection attributes are forbidden")
    options = attributes.get("options", [None])[0]
    if options is not None and options != "-c role=" + role:
        raise ValueError("Startup role must match the database operation")
    if environment.get("SQL_USER") != role and options != "-c role=" + role:
        raise ValueError("Identity login requires the explicit least-privilege startup role")
    return {"host": host, "database": database, "role": role, "tls": "verify-full", "ca_file": str(ca)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--operation", choices=("migration", "runtime"), default="migration")
    parser.add_argument("--allow-local-test", action="store_true")
    args = parser.parse_args()
    try:
        validate(os.environ, args.operation, args.allow_local_test)
        print("CONNECTION_POLICY_OK verified TLS and least-privilege role settings")
    except (ValueError, OSError) as error:
        print("Connection rejected: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())