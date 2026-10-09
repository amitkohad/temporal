import os
import runpy
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'terraform-private-archive.py'

class ArchiveTest(unittest.TestCase):
    def test_runtime_artifacts_and_unselected_inputs_are_excluded(self):
        with tempfile.TemporaryDirectory() as temporary:
            original = Path.cwd()
            os.chdir(temporary)
            try:
                Path('.deployment-local').mkdir()
                root = Path('infra/terraform')
                fixtures = [
                    'foundation/azure/main.tf',
                    'foundation/azure/.terraform.lock.hcl',
                    'foundation/azure/staging.tfvars',
                    'foundation/azure/terraform.tfstate',
                    'foundation/azure/terraform.tfstate.migrated',
                    'foundation/azure/reviewed.tfplan',
                    'foundation/azure/backend.local.tf',
                    'foundation/azure/.terraform/provider.tf',
                    'foundation/azure/tests/fixture.tf',
                    'runner/azure/staging.tfvars.json',
                    'environments/azure/staging.tfvars',
                    'bootstrap/azure/credentials.tfvars',
                ]
                for fixture in fixtures:
                    path = root / fixture
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text('fixture')
                runpy.run_path(str(SCRIPT))
                with zipfile.ZipFile('.deployment-local/terraform-private.zip') as archive:
                    self.assertEqual(set(archive.namelist()), {
                        'foundation/azure/main.tf',
                        'foundation/azure/.terraform.lock.hcl',
                        'foundation/azure/staging.tfvars',
                        'runner/azure/staging.tfvars.json',
                    })
            finally:
                os.chdir(original)

if __name__ == '__main__':
    unittest.main()