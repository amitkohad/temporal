[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]{3,24}$')][string]$StorageAccountName,
    [ValidateSet('bootstrap','infrastructure','platform')][string[]]$Containers = @('bootstrap','infrastructure','platform'),
    [ValidateSet('vm-nexusflow-stg-ci-runner')][string]$VmName = 'vm-nexusflow-stg-ci-runner',
    [ValidatePattern('^(psql-nexusflow-stg-ci-7c5841\.postgres\.database\.azure\.com|kv-nxf-stg-ci-7c5841\.vault\.azure\.net|[a-z0-9-]+\.[a-z0-9-]+\.privatelink\.centralindia\.azmk8s\.io)$')][string[]]$PrivateHosts = @()
)
$ErrorActionPreference = 'Stop'
$runnerBranch = & git branch --show-current
if ($LASTEXITCODE -ne 0 -or $runnerBranch -ne 'codex/001-azure-temporal-deployment') { throw 'Use the authoritative deployment branch.' }
$runnerAccount = & az account show --query id -o tsv
if ($LASTEXITCODE -ne 0 -or $runnerAccount -ne 'aa228172-c4ae-4c29-bd05-dcdcebb70ff4') { throw 'Wrong Azure subscription.' }
# Only reviewed nonsecret literals are interpolated into the remote script.
$runnerScript = @'
set -eu
python3 - <<'PY'
import json, socket, urllib.request, urllib.error, datetime, ipaddress, uuid
account = "ACCOUNT_PLACEHOLDER"
containers = CONTAINERS_PLACEHOLDER
private_hosts = HOSTS_PLACEHOLDER
host = account + ".blob.core.windows.net"
def private_addresses(hostname, port):
    resolved = sorted({result[4][0] for result in socket.getaddrinfo(hostname, port)})
    if not resolved or any(not ipaddress.ip_address(address).is_private for address in resolved):
        raise SystemExit("Endpoint did not resolve exclusively to private addresses: " + hostname)
    return resolved
addresses = private_addresses(host, 443)
request = urllib.request.Request("http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F", headers={"Metadata": "true"})
with urllib.request.urlopen(request, timeout=30) as response:
    token = json.load(response)["access_token"]
def blob_request(url, method="GET", headers=None, expected=200):
    request_headers = {"Authorization": "Bearer " + token, "x-ms-version": "2023-11-03", "x-ms-date": datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT")}
    request_headers.update(headers or {})
    request = urllib.request.Request(url, data=b"" if method == "PUT" else None, method=method, headers=request_headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != expected:
            raise SystemExit("Unexpected Blob response status")
        return dict(response.headers)
for container in containers:
    root = "https://" + host + "/" + container
    blob_request(root + "?restype=container&comp=list&maxresults=1")
    probe = root + "/runner-lease-probe-" + uuid.uuid4().hex
    lease_id = str(uuid.uuid4())
    created = False
    leased = False
    try:
        blob_request(probe, "PUT", {"x-ms-blob-type": "BlockBlob", "If-None-Match": "*"}, 201)
        created = True
        blob_request(probe + "?comp=lease", "PUT", {"x-ms-lease-action": "acquire", "x-ms-lease-duration": "15", "x-ms-proposed-lease-id": lease_id}, 201)
        leased = True
        try:
            blob_request(probe + "?comp=lease", "PUT", {"x-ms-lease-action": "acquire", "x-ms-lease-duration": "15"}, 201)
        except urllib.error.HTTPError as error:
            if error.code != 409:
                raise
        else:
            raise SystemExit("Concurrent lease unexpectedly succeeded")
        print("STATE_LEASE_OK " + container)
    finally:
        try:
            if leased:
                try:
                    blob_request(probe + "?comp=lease", "PUT", {"x-ms-lease-action": "release", "x-ms-lease-id": lease_id}, 200)
                except urllib.error.HTTPError as error:
                    if error.code not in (409, 412):
                        raise
        finally:
            if created:
                blob_request(probe, "DELETE", expected=202)
    print("STATE_ACCESS_OK " + container)
print("PRIVATE_DNS_OK " + ",".join(addresses))
for private_host in private_hosts:
    port = 5432 if private_host.endswith(".postgres.database.azure.com") else 443
    private_addresses(private_host, port)
    with socket.create_connection((private_host, port), timeout=15):
        pass
    print("PRIVATE_TCP_OK " + private_host + ":" + str(port))
PY
'@
$runnerScript = $runnerScript.Replace('ACCOUNT_PLACEHOLDER', $StorageAccountName).Replace('CONTAINERS_PLACEHOLDER', (ConvertTo-Json -InputObject @($Containers) -Compress)).Replace('HOSTS_PLACEHOLDER', (ConvertTo-Json -InputObject @($PrivateHosts) -Compress))
$runnerTemp = Join-Path ([IO.Path]::GetTempPath()) ('runner-probe-' + [guid]::NewGuid().ToString('N') + '.sh')
try {
    [IO.File]::WriteAllText($runnerTemp, $runnerScript.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
    $runnerResultText = & az vm run-command invoke --resource-group rg-nexusflow --name $VmName --command-id RunShellScript --scripts ('@' + $runnerTemp) --only-show-errors -o json
    if ($LASTEXITCODE -ne 0) { throw 'Azure Run Command failed.' }
    $runnerResult = $runnerResultText | ConvertFrom-Json
    $runnerMessages = ($runnerResult.value | ForEach-Object { $_.message }) -join "`n"
    foreach ($runnerContainer in $Containers) {
        if ($runnerMessages -notmatch ('STATE_ACCESS_OK ' + [regex]::Escape($runnerContainer))) { throw "Private state probe failed for $runnerContainer. $runnerMessages" }
        if ($runnerMessages -notmatch ('STATE_LEASE_OK ' + [regex]::Escape($runnerContainer))) { throw "Blob lease probe failed for $runnerContainer. $runnerMessages" }
    }
    if ($runnerMessages -notmatch 'PRIVATE_DNS_OK') { throw "Private DNS probe failed. $runnerMessages" }
    foreach ($runnerHost in $PrivateHosts) {
        if ($runnerMessages -notmatch ('PRIVATE_TCP_OK ' + [regex]::Escape($runnerHost) + ':')) { throw "Private TCP probe failed for $runnerHost. $runnerMessages" }
    }
    Write-Output $runnerMessages
} finally {
    Remove-Item -LiteralPath $runnerTemp -Force -ErrorAction SilentlyContinue
}
