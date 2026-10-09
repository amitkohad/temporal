#!/usr/bin/env bash
set -euo pipefail
# An attended caller supplies the short-lived encoded_jit_config over stdin.
# The installed official runner package must already have its digest verified.
if [ "$#" -ne 1 ] || [ ! -x "$1/run.sh" ]; then
  echo 'Usage: runner-jit.sh /path/to/verified/github-runner-package' >&2
  exit 2
fi
runner_package=$(realpath "$1")
runner_work=$(mktemp -d /tmp/nexusflow-jit.XXXXXXXX)
chmod 700 "$runner_work"
cleanup() {
  unset runner_jit_config
  rm -rf -- "$runner_work"
}
trap cleanup EXIT INT TERM
cp -a "$runner_package/." "$runner_work/"
IFS= read -r runner_jit_config
if [ -z "$runner_jit_config" ]; then
  echo 'Missing encoded_jit_config.' >&2
  exit 2
fi
cd "$runner_work"
# GitHub JIT runners accept one job and remove their registration afterward.
./run.sh --jitconfig "$runner_jit_config"