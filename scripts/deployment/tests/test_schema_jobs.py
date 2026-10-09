"""Check explicit schema Jobs for credential, execution and pod security boundaries."""
import copy
import json
import pathlib
import re
import importlib.util
import subprocess
import time
import types
import unittest
from unittest import mock
import base64

ROOT = pathlib.Path(__file__).resolve().parents[3]
PAIRS = {'temporal': 'persistence', 'temporal_visibility': 'visibility'}


def load_jobs(text):
    text = '\n'.join(line for line in text.splitlines() if not line.startswith('#'))
    return [json.loads(document) for document in re.split(r'(?m)^---\s*$', text) if document.strip()]


def validate_job(job, rendered=False):
    if job.get('apiVersion') != 'batch/v1' or job.get('kind') != 'Job':
        raise ValueError('Schema operations must be explicit Jobs')
    if job['metadata'].get('annotations'):
        raise ValueError('Schema Jobs must not use automatic chart hooks')
    spec = job['spec']
    if (spec.get('backoffLimit') != 0 or spec.get('completions') != 1 or spec.get('parallelism') != 1
            or not 0 < spec.get('activeDeadlineSeconds', 0) <= 1200):
        raise ValueError('Schema jobs must have bounded one-shot execution')
    if not rendered and spec.get('suspend') is not True:
        raise ValueError('Unqualified templates must remain suspended')
    pod = spec['template']['spec']
    if (pod.get('restartPolicy') != 'Never' or pod.get('automountServiceAccountToken') is not False
            or pod.get('hostNetwork') or pod.get('initContainers') or len(pod.get('containers', [])) != 1):
        raise ValueError('Schema job must not retry, access host networking or receive API credentials')
    security = pod['securityContext']
    if (security.get('runAsNonRoot') is not True or security.get('runAsUser') != 1000
            or security.get('runAsGroup') != 1000 or security.get('fsGroup') != 1000
            or security.get('seccompProfile', {}).get('type') != 'RuntimeDefault'):
        raise ValueError('Schema pod security context is incomplete')
    container = pod['containers'][0]
    security = container['securityContext']
    if (security.get('allowPrivilegeEscalation') is not False or security.get('readOnlyRootFilesystem') is not True
            or security.get('capabilities', {}).get('drop') != ['ALL'] or security.get('privileged')):
        raise ValueError('Schema executor must drop privileges and preserve a read-only root')
    operation = job['metadata']['labels']['nexusflow.io/schema-operation']
    if (operation not in ('initialize', 'upgrade', 'verify') or container.get('command') != ['/usr/local/bin/schema.sh']
            or container.get('args') != [operation, '/etc/temporal/release/release.json']):
        raise ValueError('Only guarded initialize, upgrade or verify operations are allowed')
    if rendered and not re.fullmatch(r'[a-z0-9.-]+\.azurecr\.io/nexusflow/temporal-migration-executor@sha256:[0-9a-f]{64}', container['image']):
        raise ValueError('A qualified source-built executor digest is required')
    env = {item['name']: item for item in container['env']}
    database = env['SCHEMA_DATABASE']['value']
    if database not in PAIRS:
        raise ValueError('Unknown schema database')
    store = PAIRS[database]
    identity = 'temporal-' + store + '-migration-identity'
    if pod['serviceAccountName'] != 'temporal-' + store + '-schema-migration':
        raise ValueError('Each database needs its own migration service account')
    for name, key in [('SCHEMA_USER', 'postgresql-principal-name'), ('AZURE_CLIENT_ID', 'client-id'), ('AZURE_TENANT_ID', 'tenant-id')]:
        if env[name].get('valueFrom', {}).get('configMapKeyRef') != {'name': identity, 'key': key, 'optional': False}:
            raise ValueError('Migration Entra identity must be explicitly mapped per database')
    if any('PASSWORD' in name or name == 'AZURE_CLIENT_SECRET' for name in env):
        raise ValueError('Password or client-secret values must not be configured')
    if (env['SCHEMA_TOKEN_HELPER'].get('value') != '/usr/local/bin/entra-token'
            or env['AZURE_FEDERATED_TOKEN_FILE'].get('value') != '/var/run/secrets/azure/tokens/azure-identity-token'
            or env['SCHEMA_CA_FILE'].get('value') != '/etc/temporal/postgresql/ca.crt'
            or env['SCHEMA_TIMEOUT_SECONDS'].get('value') != '900'
            or 'SQL_CONNECT_ATTRIBUTES' in env or 'SQL_TLS_DISABLE_HOST_VERIFICATION' in env):
        raise ValueError('Verified TLS and bounded guarded-wrapper settings are required')
    volumes = {volume['name']: volume for volume in pod['volumes']}
    if any('secret' in volume for volume in volumes.values()):
        raise ValueError('Static credential secrets are forbidden for schema jobs')
    if volumes['azure-workload-identity'].get('projected') != {'defaultMode':288, 'sources':[{'serviceAccountToken':{'audience':'api://AzureADTokenExchange','expirationSeconds':3600,'path':'azure-identity-token'}}]}:
        raise ValueError('Migration token must use an explicit Entra exchange audience and bounded projection')
    if volumes['postgresql-ca']['configMap'].get('name') != 'temporal-postgresql-ca':
        raise ValueError('PostgreSQL trust bundle must be explicitly mounted')
    mounts = {mount['name']: mount for mount in container['volumeMounts']}
    if any(mounts[name].get('readOnly') is not True for name in ('azure-workload-identity', 'postgresql-ca')):
        raise ValueError('Projected assertion and CA must remain read-only')
    if rendered and env['SCHEMA_HOST']['value'] == 'POSTGRES_PRIVATE_HOSTNAME_REQUIRED':
        raise ValueError('Resolve the verified private PostgreSQL hostname before execution')


class SchemaJobPolicyTests(unittest.TestCase):
    def setUp(self):
        self.jobs = load_jobs((ROOT / 'deploy/temporal/schemas/jobs.yaml').read_text())

    def test_explicit_operations_cover_both_databases(self):
        pairs = {(job['spec']['template']['spec']['containers'][0]['args'][0],
                  next(e['value'] for e in job['spec']['template']['spec']['containers'][0]['env'] if e['name'] == 'SCHEMA_DATABASE'))
                 for job in self.jobs}
        self.assertEqual(pairs, {(op, db) for op in ('initialize', 'upgrade', 'verify') for db in PAIRS})
        for job in self.jobs:
            validate_job(job)

    def test_unqualified_templates_cannot_pass_execution_gate(self):
        for job in self.jobs:
            with self.subTest(job=job['metadata']['name']), self.assertRaises(ValueError):
                validate_job(job, rendered=True)

    def test_automatic_hooks_and_retries_are_rejected(self):
        for change in ('hook', 'retry', 'resume'):
            job = copy.deepcopy(self.jobs[0])
            if change == 'hook': job['metadata']['annotations'] = {'helm.sh/hook': 'post-install'}
            elif change == 'retry': job['spec']['backoffLimit'] = 3
            else: job['spec']['suspend'] = False
            with self.subTest(change=change), self.assertRaises(ValueError):
                validate_job(job)

    def test_runtime_identity_is_rejected(self):
        job = copy.deepcopy(self.jobs[0])
        job['spec']['template']['spec']['serviceAccountName'] = 'temporal-runtime'
        with self.assertRaises(ValueError): validate_job(job)

    def test_wrong_audience_or_missing_identity_reference_is_rejected(self):
        for change in ('audience', 'client'):
            job = copy.deepcopy(self.jobs[0])
            pod = job['spec']['template']['spec']
            if change == 'audience':
                next(v for v in pod['volumes'] if v['name'] == 'azure-workload-identity')['projected']['sources'][0]['serviceAccountToken']['audience'] = 'kubernetes.default.svc'
            else:
                env = pod['containers'][0]['env']
                next(e for e in env if e['name'] == 'AZURE_CLIENT_ID')['valueFrom']['configMapKeyRef']['key'] = 'runtime-client-id'
            with self.subTest(change=change), self.assertRaises(ValueError): validate_job(job)

    def test_privileged_or_writable_executor_is_rejected(self):
        for key, value in [('allowPrivilegeEscalation', True), ('readOnlyRootFilesystem', False)]:
            job = copy.deepcopy(self.jobs[0])
            job['spec']['template']['spec']['containers'][0]['securityContext'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): validate_job(job)

    def test_inline_password_and_direct_sql_drop_are_rejected(self):
        for change in ('password', 'drop'):
            job = copy.deepcopy(self.jobs[0])
            container = job['spec']['template']['spec']['containers'][0]
            if change == 'password': container['env'].append({'name':'SQL_PASSWORD','value':'not-permitted'})
            else: container['command'] = ['/usr/local/bin/temporal-sql-tool']; container['args'] = ['drop-database']
            with self.subTest(change=change), self.assertRaises(ValueError): validate_job(job)

    def test_fresh_token_is_obtained_for_each_bounded_connection(self):
        spec = importlib.util.spec_from_file_location('schema_operation', ROOT / 'scripts/deployment/schema-operation.py')
        operation = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(operation)
        payload = base64.urlsafe_b64encode(json.dumps({'exp':int(time.time())+3600}).encode()).decode().rstrip('=')
        responses = [types.SimpleNamespace(stdout='header.'+payload+'.signature-one'), types.SimpleNamespace(stdout='header.'+payload+'.signature-two')]
        with mock.patch.object(operation, 'hash_file', return_value='verified-helper-sha'), mock.patch.object(operation.subprocess, 'run', side_effect=responses) as acquire:
            first = operation.renewable_auth({}, (pathlib.Path('/qualified/entra-token'), 'verified-helper-sha'), 600)
            second = operation.renewable_auth({}, (pathlib.Path('/qualified/entra-token'), 'verified-helper-sha'), 600)
        self.assertEqual(acquire.call_count, 2)
        self.assertNotEqual(first['SQL_PASSWORD'], second['SQL_PASSWORD'])
        self.assertEqual(acquire.call_args.kwargs['stderr'], subprocess.DEVNULL)
        self.assertEqual(acquire.call_args.kwargs['timeout'], 30)

    def test_executor_uses_pinned_os_and_fork_built_artifacts(self):
        dockerfile = (ROOT / 'docker/targets/schema-runner.Dockerfile').read_text()
        self.assertRegex(dockerfile, r'FROM debian:bookworm-slim@sha256:[0-9a-f]{64}')
        self.assertIn('release/build/bin/temporal-sql-tool', dockerfile)
        self.assertIn('release/executor/entra-token', dockerfile)
        self.assertIn('schema-operation.py', dockerfile)
        self.assertIn('USER 1000:1000', dockerfile)
        self.assertNotIn('temporalio/server', dockerfile)
        self.assertNotIn('temporal.download', dockerfile)


if __name__ == '__main__':
    unittest.main()
