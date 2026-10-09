"""Check the release workflows' credential and publication boundaries."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]


def check_read_only_validation(text):
    forbidden = [r'\bsecrets\.', r'id-token:', r'\benvironment:', r'uses:\s*azure/login@',
                 r'\baz\s+', r'\bdocker\s+(push|login)\b', r'pull_request_target:', r'workflow_run:']
    if any(re.search(pattern, text) for pattern in forbidden):
        raise ValueError('Validation must not receive Azure/publication credentials or privileged events')
    if not re.search(r'permissions:\s*\n\s+contents: read\s*\n', text):
        raise ValueError('Validation needs explicit read-only repository permissions')


def check_release_boundary(text):
    if '  workflow_dispatch:' not in text or re.search(r'^  (push|pull_request|workflow_run):', text, re.M):
        raise ValueError('Publication must be explicitly dispatched')
    candidate, publish = text.split('\n  publish:\n', 1)
    if 'id-token: write' in candidate or 'azure/login@' in candidate or re.search(r'\bdocker push\b', candidate):
        raise ValueError('Candidate build must be credential-free')
    required = ['needs: candidate', 'environment: staging', 'id-token: write',
                "github.ref == 'refs/heads/codex/001-azure-temporal-deployment'",
                "vars.AZURE_TEMPORAL_PUBLISH_ENABLED == 'true'",
                "vars.AZURE_TEMPORAL_OIDC_SUBJECT_VERIFIED == 'true'",
                'validate-release.sh', '--require-published', 'if: always()']
    if any(item not in publish for item in required):
        raise ValueError('Publication is missing a trust, candidate-validation or credential-cleanup gate')
    if re.search(r'\b(terraform (apply|destroy)|kubectl|helm|temporal-sql-tool)\b', text):
        raise ValueError('Image publication must not deploy infrastructure or initialize databases')


def check_source_only_workflow(text):
    if re.search(r'temporalio/(server|admin-tools)(?:[:@\s]|$)|temporalio/cli/releases|build-docker-images|:latest(?:[\s\"\']|$)', text):
        raise ValueError('Deployment images must use the dedicated source build and immutable references')


class WorkflowPolicyTests(unittest.TestCase):
    def setUp(self):
        self.validation = (ROOT / '.github/workflows/azure-temporal-validate.yml').read_text()
        self.release = (ROOT / '.github/workflows/azure-temporal-release.yml').read_text()

    def test_validation_has_no_privileged_boundary(self):
        check_read_only_validation(self.validation)
        self.assertIn('  pull_request:', self.validation)
        self.assertIn('  push:', self.validation)

    def test_validation_rejects_credential_or_push_addition(self):
        for addition in ('\nsecrets.TOKEN\n', '\nid-token: write\n', '\nrun: docker push image\n', '\npull_request_target:\n'):
            with self.subTest(addition=addition), self.assertRaises(ValueError):
                check_read_only_validation(self.validation + addition)

    def test_release_is_explicit_and_gated(self):
        check_release_boundary(self.release)

    def test_release_rejects_removed_publication_gate(self):
        for gate in ('needs: candidate', 'environment: staging', 'if: always()', "vars.AZURE_TEMPORAL_OIDC_SUBJECT_VERIFIED == 'true'"):
            with self.subTest(gate=gate), self.assertRaises(ValueError):
                check_release_boundary(self.release.replace(gate, 'removed'))

    def test_release_rejects_automatic_publish_event(self):
        with self.assertRaises(ValueError):
            check_release_boundary(self.release.replace('  workflow_dispatch:', '  push:'))

    def test_actions_are_immutable_commit_pins(self):
        for workflow in (self.validation, self.release):
            actions = re.findall(r'^\s+uses: (\S+)', workflow, re.M)
            self.assertTrue(actions)
            for action in actions:
                self.assertRegex(action, r'^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+@[0-9a-f]{40}$')

    def test_source_inputs_are_data_not_shell_expressions(self):
        self.assertIn('SOURCE_COMMIT: ${{ inputs.source_commit }}', self.release)
        self.assertIn('git merge-base --is-ancestor "$SOURCE_COMMIT" "$GITHUB_SHA"', self.release)
        runs = re.findall(r'(?m)^        run: \|\n((?:          .*\n|\n)+)', self.release)
        self.assertTrue(runs)
        for run in runs:
            self.assertNotIn('${{ inputs.source_commit }}', run)
        for workflow in (self.validation, self.release):
            self.assertIn('bash scripts/deployment/build-source.sh "$SOURCE_COMMIT"', workflow)
            self.assertNotIn('build-docker-images', workflow)
            self.assertNotIn('cli-version', workflow)

    def test_scanner_download_has_fixed_release_and_verified_digest(self):
        script = (ROOT / 'scripts/deployment/install-release-tools.sh').read_text()
        self.assertIn('/download/v0.75.0/trivy_0.75.0_Linux-64bit.tar.gz', script)
        self.assertIn('c6e65abddb348e25f10549df887045629cf28cc72453cd1c63acb717316b3f3f', script)
        self.assertIn('sha256sum --check --status', script)
        self.assertNotIn('/latest/', script)

    def test_published_images_receive_independent_remote_verification(self):
        self.assertIn("['docker', 'manifest', 'inspect', reference]", self.release)
        self.assertIn("remote.get('config', {}).get('digest') != image_id", self.release)
        self.assertIn("or 'manifests' in remote", self.release)
        self.assertIn("commit + '-' + image_id[7:]", self.release)
        self.assertIn('Existing candidate tag refers to different content; refusing overwrite', self.release)

    def test_workflows_follow_source_only_policy(self):
        check_source_only_workflow(self.validation)
        check_source_only_workflow(self.release)

    def test_dirty_driver_is_rejected_before_azure_login(self):
        gate = "metadata.get('build_driver', {}).get('dirty') is not False"
        self.assertIn(gate, self.release)
        self.assertLess(self.release.index(gate), self.release.index('uses: azure/login@'))
        self.assertLess(self.release.index(gate), self.release.index("['docker', 'push', tag]"))

    def test_source_only_policy_rejects_prebuilt_cli_or_mutable_image(self):
        for addition in ('\ndocker pull temporalio/server:1.33.0\n',
                         '\ndocker pull temporalio/admin-tools@sha256:abc\n',
                         '\ncurl https://github.com/temporalio/cli/releases/download/binary\n',
                         '\ndocker pull nexusflow/temporal-server:latest\n'):
            with self.subTest(addition=addition), self.assertRaises(ValueError):
                check_source_only_workflow(self.validation + addition)


if __name__ == '__main__':
    unittest.main()
