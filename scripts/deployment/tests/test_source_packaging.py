"""Verify packaging policy without Docker or network access."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]


class SourcePackagingTest(unittest.TestCase):
    def test_runtime_images_use_same_nonroot_digest_base_and_direct_binaries(self):
        for filename, binary in [('deployment-server.Dockerfile', 'temporal-server'), ('sql-tools.Dockerfile', 'temporal-sql-tool')]:
            with self.subTest(image=filename):
                source = (ROOT / 'docker/targets' / filename).read_text()
                self.assertEqual(re.findall(r'^FROM (.+)$', source, re.M), ['${RUNTIME_BASE}'])
                self.assertIn('USER 1000:1000', source)
                self.assertIn('ENTRYPOINT ["/usr/local/bin/' + binary + '"]', source)
                self.assertNotRegex(source, r'(?i)temporalio/|curl|wget|ADD https?://')
                self.assertNotRegex(source, r'^RUN ', 'Packaging must not install mutable packages')

    def test_sql_tools_contains_schemas_and_no_downloaded_cli(self):
        source = (ROOT / 'docker/targets/sql-tools.Dockerfile').read_text()
        copies = re.findall(r'^COPY.*$', source, re.M)
        self.assertEqual(len(copies), 2)
        self.assertIn('schema/postgresql/v12', copies[1])
        self.assertNotRegex(source, r'admin-tools|temporal-cli|/usr/local/bin/temporal(?:\s|$)')

    def test_driver_requires_full_commit_and_checks_dependency_lock_after_build(self):
        source = (ROOT / 'scripts/deployment/build-source.sh').read_text()
        self.assertIn('^[0-9a-f]{40}$', source)
        self.assertIn('git -C "$repo" archive "$commit"', source)
        self.assertIn('GOTOOLCHAIN=local', source)
        self.assertIn('go mod verify', source)
        self.assertIn('sha256sum --check "$temporary/modules.sha256"', source)
        self.assertIn('make ROOT="$source_root" temporal-server temporal-sql-tool', source)
        self.assertNotRegex(source, r'git (?:checkout|switch)|curl|wget|go install')

    def test_assembly_requires_digest_and_verifies_artifacts_before_docker(self):
        source = (ROOT / 'scripts/deployment/build-images.sh').read_text()
        self.assertIn('nonroot@sha256:[0-9a-f]{64}', source)
        self.assertLess(source.index('Artifact changed:'), source.index('docker buildx build'))
        self.assertIn('Build driver changed:', source)
        self.assertIn('Artifact file set changed', source)
        self.assertIn('--load --pull', source)
        self.assertNotIn('--push', source)
        self.assertNotIn('az ', source)


if __name__ == '__main__':
    unittest.main()