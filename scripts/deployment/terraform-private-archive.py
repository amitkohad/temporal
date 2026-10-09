import zipfile
from pathlib import Path
root = Path('infra/terraform')
inputs = {'foundation/azure/staging.tfvars', 'runner/azure/staging.tfvars.json'}
with zipfile.ZipFile('.deployment-local/terraform-private.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in root.rglob('*'):
        if not path.is_file() or '.terraform' in path.parts or 'tests' in path.parts or path.name == 'backend.local.tf':
            continue
        relative = path.relative_to(root).as_posix()
        if path.suffix == '.tf' or path.name == '.terraform.lock.hcl' or relative in inputs:
            archive.write(path, relative)