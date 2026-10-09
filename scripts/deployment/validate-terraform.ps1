# Requires PowerShell 7 and Terraform 1.10.5. This script never plans against Azure.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$taskRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

function Invoke-TaskTerraform {
    param([string[]]$Arguments)
    & terraform @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform failed: $($Arguments -join ' ')"
    }
}

Push-Location $taskRepoRoot
try {
    $taskBranch = & git branch --show-current
    if ($LASTEXITCODE -ne 0 -or $taskBranch -ne 'codex/001-azure-temporal-deployment') {
        throw 'Deployment work must stay on codex/001-azure-temporal-deployment.'
    }
    Invoke-TaskTerraform -Arguments @('fmt', '-check', '-recursive', 'infra/terraform')
    $taskRoots = @(
        'infra/terraform/modules/contracts',
        'infra/terraform/modules/azure/resource-group',
        'infra/terraform/environments/azure',
        'infra/terraform/bootstrap/azure',
        'infra/terraform/foundation/azure'
    )
    foreach ($taskRoot in $taskRoots) {
        Invoke-TaskTerraform -Arguments @("-chdir=$taskRoot", 'init', '-backend=false', '-input=false', '-lockfile=readonly', '-no-color')
        Invoke-TaskTerraform -Arguments @("-chdir=$taskRoot", 'validate', '-no-color')
        Invoke-TaskTerraform -Arguments @("-chdir=$taskRoot", 'test', '-no-color')
    }
} finally {
    Pop-Location
}
