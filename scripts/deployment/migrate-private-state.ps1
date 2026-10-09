[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('bootstrap','foundation','runner','infrastructure')][string]$Root)
$ErrorActionPreference = 'Stop'
$taskRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ((git -C $taskRepoRoot branch --show-current) -ne 'codex/001-azure-temporal-deployment') { throw 'Wrong deployment branch.' }
$taskAzurePython = 'C:/Program Files (x86)/Microsoft SDKs/Azure/CLI2/python.exe'
$taskSubscription = & $taskAzurePython -IBm azure.cli account show --query id -o tsv
if ($LASTEXITCODE -ne 0 -or $taskSubscription -ne 'aa228172-c4ae-4c29-bd05-dcdcebb70ff4') { throw 'Wrong subscription.' }
$taskDirectory = if ($Root -eq 'infrastructure') { 'environments' } else { $Root }
$taskSourceRoot = Join-Path $taskRepoRoot "infra/terraform/$taskDirectory/azure"
if (Test-Path -LiteralPath (Join-Path $taskSourceRoot '.terraform.tfstate.lock.info')) { throw 'A local operation is in progress; stop before migrating.' }
$taskStatePath = Join-Path $taskSourceRoot 'terraform.tfstate'
$taskStateHash = (Get-FileHash -LiteralPath $taskStatePath -Algorithm SHA256).Hash
$taskStateText = [IO.File]::ReadAllText($taskStatePath)
$taskState = $taskStateText | ConvertFrom-Json -Depth 100
if (-not $taskState.lineage -or $taskState.resources.Count -eq 0) { throw 'Authoritative nonempty state required.' }
$taskContainer = if ($Root -eq 'bootstrap') { 'bootstrap' } else { 'infrastructure' }
$taskKey = "nexusflow/stg/$Root.tfstate"
$taskPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($taskStateText))
$taskPython = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'migrate-private-state.py')).Replace('CONTAINER_VALUE', $taskContainer).Replace('KEY_VALUE', $taskKey).Replace('STATE_BASE64', $taskPayload)
$taskScript = "set -eu`numask 077`ntrap 'rm -f -- `"`$0`"' EXIT`npython3 - <<'PY'`n" + $taskPython + "`nPY`n"
$taskPrivateDirectory = Join-Path $taskRepoRoot '.deployment-local/migration'
New-Item -ItemType Directory -Force $taskPrivateDirectory | Out-Null
$taskIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls $taskPrivateDirectory /inheritance:r /grant:r "${taskIdentity}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot protect migration directory.' }
$taskScriptPath = Join-Path $taskPrivateDirectory "$Root.sh"
try {
    [IO.File]::WriteAllText($taskScriptPath, $taskScript.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
    $taskResultText = & $taskAzurePython -IBm azure.cli vm run-command invoke --resource-group rg-nexusflow --name vm-nexusflow-stg-ci-runner --command-id RunShellScript --scripts ('@'+$taskScriptPath) --only-show-errors -o json
    if ($LASTEXITCODE -ne 0) { throw 'Run Command failed; retain local state.' }
    $taskResult = $taskResultText | ConvertFrom-Json
    $taskMessages = ($taskResult.value | ForEach-Object { $_.message }) -join "`n"
    $taskExpectedMarker = 'REMOTE_STATE_OK ' + $taskKey + ' lineage=' + $taskState.lineage + ' serial=' + $taskState.serial + ' resources=' + $taskState.resources.Count
    if ($taskMessages -notmatch ('(?m)^' + [regex]::Escape($taskExpectedMarker) + '\r?$')) { throw "Migration verification failed. $taskMessages" }
    if ((Get-FileHash -LiteralPath $taskStatePath -Algorithm SHA256).Hash -ne $taskStateHash -or (Test-Path -LiteralPath (Join-Path $taskSourceRoot '.terraform.tfstate.lock.info'))) { throw 'Local state changed or operation started during migration; retain both states for review.' }
    $taskReceipt = @{ root=$Root; container=$taskContainer; key=$taskKey; lineage=$taskState.lineage; serial=$taskState.serial; verified_at=(Get-Date).ToUniversalTime().ToString('o') }
    [IO.File]::WriteAllText((Join-Path $taskPrivateDirectory "$Root-receipt.json"), ($taskReceipt | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    # Freeze the local copy after remote content and lease verification.
    Move-Item -LiteralPath $taskStatePath -Destination ($taskStatePath+'.migrated')
    [IO.File]::WriteAllText((Join-Path $taskSourceRoot 'backend.local.tf'), "terraform {`n  backend `"azurerm`" {}`n}`n", [Text.UTF8Encoding]::new($false))
    Write-Output $taskMessages
} finally {
    Remove-Item -LiteralPath $taskScriptPath -Force -ErrorAction SilentlyContinue
}