"""Offline decision and failure-boundary tests for schema orchestration."""
import base64
import contextlib
import json
import tempfile
import importlib.util
import io
from pathlib import Path
import time
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location('schema_operation', Path(__file__).resolve().parents[1] / 'schema-operation.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SchemaOperationTest(unittest.TestCase):
    def test_decisions_require_explicit_empty_and_older_operations(self):
        cases = [
            ('initialize', None, None, None, False, 'initialize'),
            ('initialize', '1.19', '1.0', '1.0', True, 'verify'),
            ('upgrade', '1.18', '1.0', '1.0', True, 'upgrade'),
            ('verify', '1.19', '1.0', '1.0', True, 'verify'),
        ]
        for operation, current, compatible, minimum, markers, expected in cases:
            with self.subTest(operation=operation, current=current):
                self.assertEqual(MODULE.decision(operation, current, '1.19', compatible, minimum, markers), expected)

    def test_unsafe_schema_states_refused(self):
        cases = [
            ('verify', None, None, None, False, 'Empty database'),
            ('initialize', '1.18', '1.0', '1.0', True, 'explicit upgrade'),
            ('upgrade', '1.20', '1.0', '1.0', True, 'newer'),
            ('verify', '1.19', '0.1', '1.0', True, 'compatibility'),
            ('verify', '1.19', '1.0', '1.0', False, 'schema type'),
        ]
        for operation, current, compatible, minimum, markers, message in cases:
            with self.subTest(operation=operation, current=current, message=message):
                with self.assertRaisesRegex(ValueError, message):
                    MODULE.decision(operation, current, '1.19', compatible, minimum, markers)

    def test_live_guard_loss_kills_tool_without_retry(self):
        child = mock.Mock()
        child.poll.return_value = None
        guard = mock.Mock()
        guard.query.side_effect = ValueError('guard lost')
        with mock.patch.object(MODULE.subprocess, 'Popen', return_value=child) as launch:
            with self.assertRaisesRegex(ValueError, 'guard lost'):
                MODULE.run_tool(Path('/compiled/tool'), ['update-schema'], {}, guard, time.monotonic() + 60)
        launch.assert_called_once()
        child.kill.assert_called_once()
        child.wait.assert_called_once()

    def test_command_failure_does_not_retry(self):
        child = mock.Mock()
        child.poll.return_value = 1
        child.returncode = 1
        with mock.patch.object(MODULE.subprocess, 'Popen', return_value=child) as launch:
            with self.assertRaisesRegex(ValueError, 'retain pending intent'):
                MODULE.run_tool(Path('/compiled/tool'), ['update-schema'], {}, mock.Mock(), time.monotonic() + 60)
        launch.assert_called_once()

    def test_fresh_entra_token_is_requested_for_every_invocation(self):
        claims = base64.urlsafe_b64encode(json.dumps({'exp': int(time.time()) + 1800}).encode()).decode().rstrip('=')
        token = 'header.' + claims + '.signature'
        with tempfile.TemporaryDirectory() as temporary:
            helper = Path(temporary) / 'entra-token'
            helper.write_bytes(b'compiled-source-fixture')
            contract = (helper, MODULE.hash_file(helper))
            result = mock.Mock(stdout=token)
            with mock.patch.object(MODULE.subprocess, 'run', return_value=result) as request:
                first = MODULE.renewable_auth({'PGHOST': 'private'}, contract, 600)
                second = MODULE.renewable_auth({'PGHOST': 'private'}, contract, 600)
            self.assertEqual(request.call_count, 2)
            self.assertEqual(first['PGPASSWORD'], token)
            self.assertEqual(second['SQL_PASSWORD'], token)
            self.assertEqual(request.call_args.kwargs['stderr'], MODULE.subprocess.DEVNULL)

    def test_short_lived_or_changed_helper_is_rejected(self):
        claims = base64.urlsafe_b64encode(json.dumps({'exp': int(time.time()) + 10}).encode()).decode().rstrip('=')
        with tempfile.TemporaryDirectory() as temporary:
            helper = Path(temporary) / 'entra-token'
            helper.write_bytes(b'compiled-source-fixture')
            contract = (helper, MODULE.hash_file(helper))
            with mock.patch.object(MODULE.subprocess, 'run', return_value=mock.Mock(stdout='header.' + claims + '.signature')):
                with self.assertRaisesRegex(ValueError, 'lifetime is too short'):
                    MODULE.renewable_auth({}, contract, 600)
            helper.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'helper changed'):
                MODULE.renewable_auth({}, contract, 30)

    def test_current_initialization_rerun_executes_no_ddl(self):
        statements = []
        guard = mock.Mock()
        def query(sql):
            statements.append(sql)
            if 'pg_try_advisory_lock' in sql or 'to_regnamespace' in sql:
                return ['t']
            if "to_regclass('nexusflow_migration.intent')" in sql:
                return ['f']
            if 'FROM pg_class' in sql:
                return ['5']
            if "to_regclass('public.schema_version')" in sql:
                return ['t']
            if 'FROM public.schema_version' in sql:
                return ['1.19|1.0']
            if "to_regclass('public.executions')" in sql:
                return ['t']
            raise AssertionError('Unexpected statement: ' + sql)
        guard.query.side_effect = query
        with mock.patch.dict(MODULE.os.environ, {'SCHEMA_DATABASE': 'temporal'}):
            with mock.patch.object(MODULE, 'build_contract', return_value=(Path('/compiled/tool'), Path('/schemas'), {'persistence': '1.19', 'visibility': '1.14'})):
                with mock.patch.object(MODULE, 'manifests', return_value={'1.19': {'MinCompatibleVersion': '1.0'}}):
                    with mock.patch.object(MODULE, 'connection', return_value=({}, time.monotonic() + 60)):
                        with mock.patch.object(MODULE, 'Guard', return_value=guard):
                            with mock.patch.object(MODULE, 'run_tool') as command:
                                with contextlib.redirect_stdout(io.StringIO()) as output:
                                    MODULE.execute('initialize', Path('/manifest'), True)
        command.assert_not_called()
        self.assertFalse(any(sql.startswith(('CREATE', 'INSERT', 'UPDATE', 'DELETE', 'DROP')) for sql in statements))
        self.assertIn('action=verify', output.getvalue())
        guard.close.assert_called_once()


if __name__ == '__main__':
    unittest.main()