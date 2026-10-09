[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('foundation','runner')][string]$Root,
    [Parameter(Mandatory)][ValidateSet('plan','apply','check')][string]$Mode,
    [ValidatePattern('^[0-9a-f]{64}$')][string]$PlanSha256
)
$ErrorActionPreference = 'Stop'
$taskRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ((git -C $taskRepoRoot branch --show-current) -ne 'codex/001-azure-temporal-deployment') { throw 'Wrong branch.' }
if ($Mode -eq 'apply' -and -not $PlanSha256) { throw 'Apply requires the SHA256 of the reviewed remote plan.' }
$taskAz = 'C:/Program Files (x86)/Microsoft SDKs/Azure/CLI2/python.exe'
if ((& $taskAz -IBm azure.cli account show --query id -o tsv) -ne 'aa228172-c4ae-4c29-bd05-dcdcebb70ff4') { throw 'Wrong subscription.' }
$taskArchive = Join-Path $taskRepoRoot '.deployment-local/terraform-private.zip'
Push-Location $taskRepoRoot
try {
    & $taskAz scripts/deployment/terraform-private-archive.py
    if ($LASTEXITCODE -ne 0) { throw 'Archive creation failed.' }
    $taskPayload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($taskArchive))
    $taskScript = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'terraform-private-operation.sh'))
    $taskScript = $taskScript.Replace('ROOT_VALUE',$Root).Replace('MODE_VALUE',$Mode).Replace('ARCHIVE_VALUE',$taskPayload).Replace('PLAN_VALUE',[string]$PlanSha256)
    $taskScriptPath = Join-Path $taskRepoRoot ".deployment-local/private-terraform-$Root.sh"
    [IO.File]::WriteAllText($taskScriptPath,$taskScript.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
    try {
        $taskResult = & $taskAz -IBm azure.cli vm run-command invoke --resource-group rg-nexusflow --name vm-nexusflow-stg-ci-runner --command-id RunShellScript --scripts ('@'+$taskScriptPath) --only-show-errors -o json
        if ($LASTEXITCODE -ne 0) { throw 'Private Terraform invocation failed.' }
        $taskMessages = (($taskResult | ConvertFrom-Json).value | ForEach-Object { $_.message }) -join "`n"
        $taskMarker = switch ($Mode) { apply { "PRIVATE_APPLY_OK $Root" }; check { "PRIVATE_DRIFT_OK $Root" }; plan { 'PRIVATE_PLAN_SHA256' } }
        if ($taskMessages -notmatch [regex]::Escape($taskMarker)) { throw "Private Terraform operation failed. $taskMessages" }
        Write-Output $taskMessages
    } finally { Remove-Item -LiteralPath $taskScriptPath -Force -ErrorAction SilentlyContinue }
} finally {
    Remove-Item -LiteralPath $taskArchive -Force -ErrorAction SilentlyContinue
    Pop-Location
}