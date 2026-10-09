#!/usr/bin/env bash
set -euo pipefail
umask 077
operation=/var/lib/nexusflow-terraform-operations/ROOT_VALUE
mkdir -p "$operation"
cd "$operation"
if [ 'MODE_VALUE' != apply ]; then
  printf '%s' 'ARCHIVE_VALUE' | base64 -d > configuration.zip
  rm -rf -- "$operation/configuration"
  python3 -c "import zipfile; zipfile.ZipFile('configuration.zip').extractall('configuration')"
  rm configuration.zip
  if [ ! -x ./terraform ]; then
    curl -fsSL --retry 3 https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_amd64.zip -o terraform.zip
    printf '%s\n' '0566a24f5332098b15716ebc394be503f4094acba5ba529bf5eb0698ed5e2a90  terraform.zip' | sha256sum -c - >/dev/null
    python3 -c "import zipfile; zipfile.ZipFile('terraform.zip').extract('terraform')"
    chmod 700 terraform
    rm terraform.zip
  fi
  mkdir -p plugin-cache
  export TF_PLUGIN_CACHE_DIR="$operation/plugin-cache"
  cat > backend.tfbackend <<'TF'
resource_group_name = "rg-nexusflow"
storage_account_name = "stnexusflowtf7c5841"
container_name = "infrastructure"
key = "nexusflow/stg/ROOT_VALUE.tfstate"
use_azuread_auth = true
use_msi = true
subscription_id = "aa228172-c4ae-4c29-bd05-dcdcebb70ff4"
tenant_id = "48d2ccb2-9e24-49cc-921b-89962ed5f85f"
TF
  cat > configuration/ROOT_VALUE/azure/backend.local.tf <<'TF'
terraform {
  backend "azurerm" {}
}
TF
fi
export ARM_USE_MSI=true
export ARM_SUBSCRIPTION_ID=aa228172-c4ae-4c29-bd05-dcdcebb70ff4
export ARM_TENANT_ID=48d2ccb2-9e24-49cc-921b-89962ed5f85f
root=configuration/ROOT_VALUE/azure
inputs=staging.tfvars
if [ 'ROOT_VALUE' = runner ]; then inputs=staging.tfvars.json; fi
if [ 'MODE_VALUE' = apply ]; then
  actual=$(sha256sum "$root/reviewed.tfplan" | cut -d ' ' -f 1)
  if [ "$actual" != 'PLAN_VALUE' ]; then echo 'Reviewed plan checksum mismatch'; exit 1; fi
  ./terraform -chdir="$root" apply -input=false -no-color reviewed.tfplan > apply.log 2>&1 || { tail -n 15 apply.log; exit 1; }
  rm "$root/reviewed.tfplan"
  echo 'PRIVATE_APPLY_OK ROOT_VALUE'
else
  ./terraform -chdir="$root" init -reconfigure -input=false -lockfile=readonly -backend-config="$operation/backend.tfbackend" -no-color > init.log 2>&1 || { tail -n 15 init.log; exit 1; }
  set +e
  ./terraform -chdir="$root" plan -var-file="$inputs" -detailed-exitcode -input=false -no-color -out=reviewed.tfplan > plan.log 2>&1
  result=$?
  set -e
  if [ "$result" -ne 0 ] && [ "$result" -ne 2 ]; then tail -n 15 plan.log; exit 1; fi
  if [ 'MODE_VALUE' = check ] && [ "$result" -ne 0 ]; then echo 'PRIVATE_DRIFT_FOUND ROOT_VALUE'; exit 1; fi
  ./terraform -chdir="$root" show -json reviewed.tfplan > plan.json
  python3 - <<'PY'
import json,hashlib,pathlib
root=pathlib.Path('configuration/ROOT_VALUE/azure')
plan=json.load(open('plan.json'))
for resource in plan.get('resource_changes',[]):
    actions=resource['change']['actions']
    if 'delete' in actions:
        raise SystemExit('Remote network operation refuses deletion/replacement')
    if actions not in [['no-op'],['read']]:
        print('PRIVATE_PLAN_CHANGE '+resource['address']+' '+','.join(actions))
print('PRIVATE_PLAN_SHA256 '+hashlib.sha256((root/'reviewed.tfplan').read_bytes()).hexdigest())
PY
  if [ 'MODE_VALUE' = check ]; then echo 'PRIVATE_DRIFT_OK ROOT_VALUE'; fi
fi
rm -f -- "$0"