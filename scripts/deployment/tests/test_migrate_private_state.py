"""Exercise backend migration through fake HTTP responses; no Azure access."""
import base64
import contextlib
import copy
import io
import json
from pathlib import Path
import unittest
from unittest import mock
import urllib.error


class Response(io.BytesIO):
    def __init__(self, content=b"", status=200):
        if isinstance(content, dict):
            content = json.dumps(content).encode()
        super().__init__(content)
        self.status = status


class MigrationTest(unittest.TestCase):
    state = {
        "lineage": "fixture-lineage",
        "serial": 4,
        "resources": [{"type": "azurerm_virtual_network", "name": "fixture"}],
        "outputs": {"network": {"value": "fixture-id", "type": "string"}},
    }

    def run_migration(self, responses):
        template = (Path(__file__).resolve().parents[1] / "migrate-private-state.py").read_text()
        payload = base64.b64encode(json.dumps(self.state).encode()).decode()
        source = template.replace("CONTAINER_VALUE", "infrastructure").replace(
            "KEY_VALUE", "nexusflow/stg/foundation.tfstate"
        ).replace("STATE_BASE64", payload)
        output = io.StringIO()
        with mock.patch("urllib.request.urlopen", side_effect=responses) as request:
            with contextlib.redirect_stdout(output):
                try:
                    exec(compile(source, "migration-template", "exec"), {})
                    error = None
                except BaseException as caught:
                    error = caught
        return request.call_args_list, output.getvalue(), error

    @staticmethod
    def missing():
        return urllib.error.HTTPError("https://fixture", 404, "Not Found", {}, None)

    @staticmethod
    def token():
        return Response({"access_token": "offline-fixture-token"})

    def test_empty_destination_seed_is_conditional_and_verified_under_lease(self):
        calls, output, error = self.run_migration([
            self.token(), self.missing(), Response(status=201),
            Response(status=201), Response(self.state), Response(status=200),
        ])
        self.assertIsNone(error)
        seed = calls[2].args[0]
        self.assertEqual(seed.get_method(), "PUT")
        self.assertEqual(seed.get_header("If-none-match"), "*")
        self.assertEqual(json.loads(seed.data), self.state)
        acquire = calls[3].args[0]
        release = calls[5].args[0]
        self.assertEqual(acquire.get_header("X-ms-lease-action"), "acquire")
        self.assertEqual(release.get_header("X-ms-lease-action"), "release")
        self.assertEqual(acquire.get_header("X-ms-proposed-lease-id"), release.get_header("X-ms-lease-id"))
        self.assertIn("REMOTE_STATE_OK nexusflow/stg/foundation.tfstate lineage=fixture-lineage serial=4", output)

    def test_identical_destination_resumes_without_seed_put(self):
        calls, output, error = self.run_migration([
            self.token(), Response(self.state), Response(status=201),
            Response(self.state), Response(status=200),
        ])
        self.assertIsNone(error)
        writes = [call.args[0] for call in calls if call.args[0].get_method() == "PUT"]
        self.assertEqual([request.get_header("X-ms-lease-action") for request in writes], ["acquire", "release"])
        self.assertIn("REMOTE_STATE_OK", output)

    def test_different_lineage_refuses_without_any_write(self):
        remote = copy.deepcopy(self.state)
        remote["lineage"] = "unrelated-lineage"
        calls, output, error = self.run_migration([self.token(), Response(remote)])
        self.assertIsInstance(error, SystemExit)
        self.assertIn("differs", str(error))
        self.assertEqual([call.args[0].get_method() for call in calls], ["GET", "GET"])
        self.assertNotIn("REMOTE_STATE_OK", output)

    def test_acquire_conflict_emits_no_success_marker(self):
        conflict = urllib.error.HTTPError("https://fixture?comp=lease", 409, "Lease held", {}, None)
        calls, output, error = self.run_migration([self.token(), Response(self.state), conflict])
        self.assertIsInstance(error, urllib.error.HTTPError)
        self.assertEqual(error.code, 409)
        self.assertEqual(len(calls), 3)
        self.assertEqual(calls[-1].args[0].get_header("X-ms-lease-action"), "acquire")
        self.assertNotIn("REMOTE_STATE_OK", output)

    def test_verification_failure_releases_acquired_lease(self):
        changed = copy.deepcopy(self.state)
        changed["serial"] = 5
        calls, output, error = self.run_migration([
            self.token(), Response(self.state), Response(status=201),
            Response(changed), Response(status=200),
        ])
        self.assertIsInstance(error, SystemExit)
        self.assertEqual(calls[-1].args[0].get_header("X-ms-lease-action"), "release")
        self.assertEqual(calls[2].args[0].get_header("X-ms-proposed-lease-id"), calls[-1].args[0].get_header("X-ms-lease-id"))
        self.assertNotIn("REMOTE_STATE_OK", output)

    def test_atomic_seed_conflict_does_not_retry_unconditional_write(self):
        conflict = urllib.error.HTTPError("https://fixture", 412, "Already created", {}, None)
        calls, output, error = self.run_migration([self.token(), self.missing(), conflict])
        self.assertIsInstance(error, urllib.error.HTTPError)
        self.assertEqual(error.code, 412)
        self.assertEqual(len(calls), 3)
        self.assertEqual(calls[-1].args[0].get_header("If-none-match"), "*")
        self.assertNotIn("REMOTE_STATE_OK", output)


if __name__ == "__main__":
    unittest.main()