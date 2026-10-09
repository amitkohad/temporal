#!/usr/bin/env bash
# Build only committed application source; the driver is recorded independently.
set -euo pipefail
umask 077
if [[ $# != 2 || ! $1 =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Usage: build-source.sh FULL_COMMIT EMPTY_OUTPUT_DIRECTORY' >&2; exit 2
fi
commit=$1
repo=$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)
branch=$(git -C "$repo" branch --show-current)
if [[ $branch != codex/001-azure-temporal-deployment ]]; then
  [[ -z $branch && ${GITHUB_ACTIONS:-false} == true && ${GITHUB_REPOSITORY:-} == amitkohad/temporal ]] || { echo 'Wrong deployment branch' >&2; exit 1; }
  if [[ ${GITHUB_REF:-} == refs/heads/codex/001-azure-temporal-deployment ]]; then
    [[ ${GITHUB_EVENT_NAME:-} == push || ${GITHUB_EVENT_NAME:-} == workflow_dispatch ]] || { echo 'Unexpected authoritative-branch event' >&2; exit 1; }
  else
    [[ ${GITHUB_EVENT_NAME:-} == pull_request && ${GITHUB_BASE_REF:-} == codex/001-azure-temporal-deployment && ${GITHUB_REF:-} =~ ^refs/pull/[0-9]+/merge$ ]] || { echo 'Unexpected detached CI source' >&2; exit 1; }
  fi
fi
origin=$(git -C "$repo" remote get-url origin)
case "$origin" in https://github.com/amitkohad/temporal|https://github.com/amitkohad/temporal.git|git@github.com:amitkohad/temporal.git) ;; *) echo 'Source must be the approved fork' >&2; exit 1 ;; esac
[[ $(git -C "$repo" rev-parse "$commit^{commit}") == "$commit" ]] || exit 1
git -C "$repo" merge-base --is-ancestor "$commit" HEAD || { echo 'Source commit must belong to the checked-out fork history' >&2; exit 1; }
for tool in go make python3 tar sha256sum; do command -v "$tool" >/dev/null || { echo "Missing build tool: $tool" >&2; exit 1; }; done
[[ $(go env GOVERSION) == go1.27.2 ]] || { echo 'Go 1.27.2 is required' >&2; exit 1; }
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'Use the Linux amd64 builder' >&2; exit 1; }
mkdir -p "$2"
out=$(cd "$2" && pwd)
[[ -z $(find "$out" -mindepth 1 -maxdepth 1 -print -quit) ]] || { echo 'Output directory must be empty' >&2; exit 1; }
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
python3 - "$repo" "$temporary/driver-files.json" <<'PY'
import hashlib, json, pathlib, sys
repo = pathlib.Path(sys.argv[1])
drivers = ['scripts/deployment/build-source.sh', 'scripts/deployment/build-images.sh', 'docker/targets/deployment-server.Dockerfile', 'docker/targets/sql-tools.Dockerfile']
snapshot = {name: hashlib.sha256((repo / name).read_bytes()).hexdigest() for name in drivers}
pathlib.Path(sys.argv[2]).write_text(json.dumps(snapshot, sort_keys=True))
PY
mkdir "$temporary/source"
git -C "$repo" archive "$commit" | tar -x -C "$temporary/source"
source_root="$temporary/source"
export GOOS=linux GOARCH=amd64 CGO_ENABLED=0 GOTOOLCHAIN=local
export GOFLAGS='-trimpath -buildvcs=false'
export GOPROXY=${GOPROXY:-https://proxy.golang.org,direct}
export GOSUMDB=sum.golang.org
(cd "$source_root" && sha256sum go.mod go.sum > "$temporary/modules.sha256" && go mod download && go mod verify && make ROOT="$source_root" temporal-server temporal-sql-tool && sha256sum --check "$temporary/modules.sha256")
mkdir -p "$out/bin" "$out/schema/postgresql"
cp "$source_root/temporal-server" "$source_root/temporal-sql-tool" "$out/bin/"
cp -R "$source_root/schema/postgresql/v12" "$out/schema/postgresql/"
chmod 0555 "$out/bin/temporal-server" "$out/bin/temporal-sql-tool"
python3 - "$repo" "$source_root" "$out" "$commit" "$temporary/driver-files.json" <<'PY'
import hashlib, json, os, pathlib, re, subprocess, sys
repo, source, out = map(pathlib.Path, sys.argv[1:4])
commit = sys.argv[4]
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
files = {p.relative_to(out).as_posix(): digest(p) for p in sorted(out.rglob('*')) if p.is_file()}
version_source = (source / 'common/headers/version_checker.go').read_text()
schema_source = (source / 'schema/postgresql/v12/version.go').read_text()
def constant(text, name):
    match = re.search(r'\b' + name + r'\s*=\s*"([^"]+)"', text)
    if not match:
        raise SystemExit('Missing source version constant: ' + name)
    return match.group(1)
drivers = ['scripts/deployment/build-source.sh', 'scripts/deployment/build-images.sh', 'docker/targets/deployment-server.Dockerfile', 'docker/targets/sql-tools.Dockerfile']
driver_files = json.loads(pathlib.Path(sys.argv[5]).read_text())
if driver_files != {name: digest(repo / name) for name in drivers}:
    raise SystemExit('Build driver changed during compilation; discard candidate artifacts')
metadata = {
    'schema_version': 1,
    'source_repository': 'https://github.com/amitkohad/temporal',
    'source_commit': commit,
    'source_dirty': False,
    'build_driver': {
        'repository_commit': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
        'sha256': hashlib.sha256(json.dumps(driver_files, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
        'files': driver_files,
        'dirty': bool(subprocess.check_output(['git', '-C', str(repo), 'status', '--porcelain', '--', *drivers], text=True).strip()),
    },
    'platform': 'linux/amd64',
    'toolchain': 'go1.27.2',
    'builder_image': os.environ.get('BUILD_BUILDER_IMAGE_ID'),
    'builder_parent_image': os.environ.get('BUILD_TOOLCHAIN_IMAGE'),
    'build_flags': {'GOFLAGS': os.environ['GOFLAGS'], 'CGO_ENABLED': '0', 'make_targets': ['temporal-server', 'temporal-sql-tool']},
    'server_version': constant(version_source, 'ServerVersion'),
    'schema_versions': {'persistence': constant(schema_source, 'Version'), 'visibility': constant(schema_source, 'VisibilityVersion')},
    'files': files,
}
(out / 'build-metadata.json').write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n')
print('SOURCE_BUILD_OK commit=' + commit + ' files=' + str(len(files)))
PY