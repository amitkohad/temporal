"""Seed an empty private Terraform backend without overwriting another lineage."""
import base64
import json
import urllib.error
import urllib.request
import uuid

ACCOUNT = "stnexusflowtf7c5841"
CONTAINER = "CONTAINER_VALUE"
KEY = "KEY_VALUE"
PAYLOAD = base64.b64decode("STATE_BASE64")
STATE = json.loads(PAYLOAD)
if not STATE.get("lineage") or not STATE.get("resources"):
    raise SystemExit("Nonempty authoritative state required")
request = urllib.request.Request(
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F",
    headers={"Metadata": "true"},
)
with urllib.request.urlopen(request, timeout=30) as response:
    token = json.load(response)["access_token"]
url = "https://" + ACCOUNT + ".blob.core.windows.net/" + CONTAINER + "/" + KEY
headers = {"Authorization": "Bearer " + token, "x-ms-version": "2023-11-03"}

def read_state():
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as response:
        return json.load(response)

def verify(remote):
    if any(remote[field] != STATE[field] for field in ["lineage", "serial", "resources", "outputs"]):
        raise SystemExit("Remote lineage/serial/content differs; migration stopped")

try:
    verify(read_state())
except urllib.error.HTTPError as error:
    if error.code != 404:
        raise SystemExit("Destination check failed: HTTP " + str(error.code))
    create_headers = dict(headers, **{"x-ms-blob-type": "BlockBlob", "If-None-Match": "*", "Content-Type": "application/json"})
    request = urllib.request.Request(url, data=PAYLOAD, headers=create_headers, method="PUT")
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 201:
            raise SystemExit("Atomic backend seed failed")
lease_id = str(uuid.uuid4())
lease_headers = dict(headers, **{"x-ms-lease-action": "acquire", "x-ms-lease-duration": "60", "x-ms-proposed-lease-id": lease_id})
request = urllib.request.Request(url + "?comp=lease", data=b"", headers=lease_headers, method="PUT")
with urllib.request.urlopen(request, timeout=30) as response:
    if response.status != 201:
        raise SystemExit("Cannot exclusively verify migrated backend")
try:
    verify(read_state())
finally:
    release_headers = dict(headers, **{"x-ms-lease-action": "release", "x-ms-lease-id": lease_id})
    urllib.request.urlopen(urllib.request.Request(url + "?comp=lease", data=b"", headers=release_headers, method="PUT"), timeout=30).close()
print("REMOTE_STATE_OK " + KEY + " lineage=" + STATE["lineage"] + " serial=" + str(STATE["serial"]) + " resources=" + str(len(STATE["resources"])))