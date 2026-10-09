#!/usr/bin/env bash
# Install the official scanner executable after verifying its immutable artifact digest.
set -euo pipefail
if [[ $# != 1 || $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
  echo 'Usage: install-release-tools.sh DESTINATION_DIRECTORY (Linux amd64 only)' >&2
  exit 2
fi
mkdir -p -- "$1"
destination=$(cd -- "$1" && pwd)
scanner_tmp=$(mktemp -d)
trap 'rm -rf -- "$scanner_tmp"' EXIT
curl --fail --silent --show-error --location --retry 3 \
  'https://github.com/aquasecurity/trivy/releases/download/v0.75.0/trivy_0.75.0_Linux-64bit.tar.gz' \
  --output "$scanner_tmp/trivy.tar.gz"
printf '%s  %s\n' 'c6e65abddb348e25f10549df887045629cf28cc72453cd1c63acb717316b3f3f' "$scanner_tmp/trivy.tar.gz" | sha256sum --check --status
# Extract only the verified binary; archive paths are not installed wholesale.
tar -xzf "$scanner_tmp/trivy.tar.gz" -C "$scanner_tmp" trivy
install -m 0755 "$scanner_tmp/trivy" "$destination/trivy"
[[ $("$destination/trivy" --version | head -n 1) == 'Version: 0.75.0' ]] || { echo 'Scanner version mismatch' >&2; exit 1; }
printf 'RELEASE_SCANNER_OK version=0.75.0\n'