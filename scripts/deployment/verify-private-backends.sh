#!/usr/bin/env bash
set -euo pipefail
umask 077
# Run only through the attended private operator after state migration.
work=$(mktemp -d /tmp/nexusflow-backend-check-XXXXXX)
trap 'rm -rf -- "$work"; rm -f -- "$0"' EXIT
cd "$work"
mkdir plugin-cache
export TF_PLUGIN_CACHE_DIR="$work/plugin-cache"
curl -fsSL --retry 3 https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_amd64.zip -o terraform.zip
printf '%s\n' '0566a24f5332098b15716ebc394be503f4094acba5ba529bf5eb0698ed5e2a90  terraform.zip' | sha256sum -c - >/dev/null
python3 -c "import zipfile; zipfile.ZipFile('terraform.zip').extract('terraform')"
chmod 700 terraform
for root in bootstrap foundation runner infrastructure; do
  mkdir "$root"
  container=infrastructure
  if [ "$root" = bootstrap ]; then container=bootstrap; fi
  cat > "$root/main.tf" <<TF
terraform {
  required_version = ">= 1.10.5, < 1.11.0"
  backend "azurerm" {
    resource_group_name = "rg-nexusflow"
    storage_account_name = "stnexusflowtf7c5841"
    container_name = "$container"
    key = "nexusflow/stg/$root.tfstate"
    use_azuread_auth = true
    use_msi = true
    subscription_id = "aa228172-c4ae-4c29-bd05-dcdcebb70ff4"
    tenant_id = "48d2ccb2-9e24-49cc-921b-89962ed5f85f"
  }
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "= 4.50.0" }
    azapi = { source = "Azure/azapi", version = "= 2.4.0" }
  }
}
TF
  ./terraform -chdir="$root" init -input=false -no-color > "$root/init.log" 2>&1 || { echo "BACKEND_INIT_FAILED $root"; exit 1; }
  ./terraform -chdir="$root" state pull > "$root/state.json"
  python3 - "$root" <<'PY'
import sys,json
root=sys.argv[1]
state=json.load(open(root+'/state.json'))
if not state.get('lineage') or not state.get('resources'):
    raise SystemExit('Empty or invalid remote state: '+root)
print('TERRAFORM_BACKEND_OK '+root+' lineage='+state['lineage']+' serial='+str(state['serial'])+' resources='+str(len(state['resources'])))
PY
done