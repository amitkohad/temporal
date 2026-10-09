import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[3] / "deploy/temporal/schemas/connection-policy.py"
SPEC = importlib.util.spec_from_file_location("schema_connection", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ConnectionPolicyTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        ca = Path(self.temporary.name) / "ca.pem"
        ca.write_text("-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----\n")
        self.environment = {"SQL_HOST": "psql.example.test", "SQL_DATABASE": "temporal", "SQL_USER": "temporal_migrator",
                            "SQL_PLUGIN": "postgres12_pgx", "SQL_TLS": "true", "SQL_TLS_CA_FILE": str(ca)}

    def test_verified_hostname_and_migrator(self):
        result = MODULE.validate(self.environment)
        self.assertEqual(result["role"], "temporal_migrator")
        self.assertEqual(result["tls"], "verify-full")

    def test_tls_and_role_weakening_denied(self):
        cases = [("SQL_TLS", "false"), ("SQL_TLS_DISABLE_HOST_VERIFICATION", "true"),
                 ("SQL_HOST", "10.42.2.4"), ("SQL_TLS_SERVER_NAME", "wrong.example.test"),
                 ("SQL_DATABASE", "postgres"), ("SQL_PLUGIN", "mysql8"),
                 ("SQL_CONNECT_ATTRIBUTES", "sslmode=require"),
                 ("SQL_CONNECT_ATTRIBUTES", "options=-c+role%3Dtemporal_runtime"),
                 ("SQL_USER", "azure-admin")]
        for key, value in cases:
            with self.subTest(key=key, value=value):
                changed = dict(self.environment, **{key: value})
                with self.assertRaises(ValueError):
                    MODULE.validate(changed)

    def test_identity_login_requires_matching_startup_role(self):
        self.environment.update(SQL_USER="identity-login", SQL_CONNECT_ATTRIBUTES="options=-c+role%3Dtemporal_migrator")
        MODULE.validate(self.environment)

    def test_missing_ca_rejected(self):
        self.environment["SQL_TLS_CA_FILE"] = str(Path(self.temporary.name) / "missing.pem")
        with self.assertRaisesRegex(ValueError, "trusted PEM"):
            MODULE.validate(self.environment)


if __name__ == "__main__":
    unittest.main()