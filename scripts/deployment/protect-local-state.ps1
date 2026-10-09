# Requires Windows PowerShell 7. DPAPI backups are readable only by this Windows user.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$taskRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $IsWindows) { throw 'DPAPI backup requires Windows; use equivalent encrypted storage on other hosts.' }
if ((git -C $taskRepoRoot branch --show-current) -ne 'codex/001-azure-temporal-deployment') { throw 'Wrong deployment branch.' }
Add-Type -AssemblyName System.Security.Cryptography.ProtectedData
$taskBackupRoot = Join-Path $taskRepoRoot '.deployment-local/state-backups'
New-Item -ItemType Directory -Force $taskBackupRoot | Out-Null
$taskIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls $taskBackupRoot /inheritance:r /grant:r "${taskIdentity}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot restrict backup access.' }
foreach ($taskRoot in @('foundation', 'bootstrap')) {
    $taskRootPath = Join-Path $taskRepoRoot "infra/terraform/$taskRoot/azure"
    $taskStatePath = Join-Path $taskRootPath 'terraform.tfstate'
    if (-not (Test-Path -LiteralPath $taskStatePath)) { throw "State missing for $taskRoot." }
    $taskStateBytes = [IO.File]::ReadAllBytes($taskStatePath)
    $taskEncrypted = [Security.Cryptography.ProtectedData]::Protect($taskStateBytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes((Join-Path $taskBackupRoot "$taskRoot-$(Get-Date -Format yyyyMMddTHHmmssfff).dpapi"), $taskEncrypted)
    foreach ($taskFile in Get-ChildItem -LiteralPath $taskRootPath -File | Where-Object { $_.Name -like '*.tfstate*' -or $_.Name -like '*.tfplan' -or $_.Name -like '*.tfvars' }) {
        & icacls $taskFile.FullName /inheritance:r /grant:r "${taskIdentity}:F" 'SYSTEM:F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Cannot restrict access to $($taskFile.Name)." }
    }
    Write-Output "Protected $taskRoot state and created a DPAPI backup."
}