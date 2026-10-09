#!/usr/bin/env bash
# Assemble local candidate images from verified source-build artifacts.
set -euo pipefail
if [[ $# != 4 || ! $2 =~ ^gcr.io/distroless/static-debian12:nonroot@sha256:[0-9a-f]{64}$ ]]; then
  echo 'Usage: build-images.sh ARTIFACT_DIRECTORY PINNED_DISTROLESS_BASE SERVER_TAG SQL_TOOLS_TAG' >&2; exit 2
fi
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
out=$(cd "$1" && pwd)
runtime=$2
server_tag=$3
sql_tag=$4
for tag in "$server_tag" "$sql_tag"; do
  [[ $tag != *:latest && $tag != *@* && $tag =~ ^[a-zA-Z0-9][a-zA-Z0-9._:/-]*:[a-zA-Z0-9._-]+$ ]] || { echo 'Explicit immutable candidate tags required' >&2; exit 1; }
done
[[ $server_tag != "$sql_tag" ]] || { echo 'Images require distinct tags' >&2; exit 1; }
python3 - "$out" "$repo" <<'PY'
import hashlib, json, pathlib, sys
out, repo = map(pathlib.Path, sys.argv[1:])
metadata = json.loads((out / 'build-metadata.json').read_text())
for name, expected in metadata['files'].items():
    path = out / name
    if pathlib.PurePosixPath(name).is_absolute() or '..' in pathlib.PurePosixPath(name).parts or path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit('Artifact changed: ' + name)
for name, expected in metadata['build_driver']['files'].items():
    if hashlib.sha256((repo / name).read_bytes()).hexdigest() != expected:
        raise SystemExit('Build driver changed: ' + name)
actual = {p.relative_to(out).as_posix() for directory in ['bin', 'schema'] for p in (out / directory).rglob('*') if p.is_file()}
if actual != set(metadata['files']):
    raise SystemExit('Artifact file set changed')
PY
readarray -t properties < <(python3 - "$out/build-metadata.json" <<'PY'
import json, sys
metadata = json.load(open(sys.argv[1]))
print(metadata['source_commit'])
print(metadata['server_version'])
print(metadata['build_driver']['sha256'])
PY
)
commit=${properties[0]}
version=${properties[1]}
driver=${properties[2]}
for kind in server sql-tools; do
  if [[ $kind == server ]]; then file=deployment-server; tag=$server_tag; else file=sql-tools; tag=$sql_tag; fi
  docker buildx build --platform linux/amd64 --load --pull \
    --file "$repo/docker/targets/$file.Dockerfile" \
    --build-arg "RUNTIME_BASE=$runtime" --build-arg "SOURCE_COMMIT=$commit" \
    --build-arg "SERVER_VERSION=$version" --build-arg "BUILD_DRIVER_SHA256=$driver" \
    --tag "$tag" "$out"
done
python3 - "$out" "$commit" "$runtime" "$server_tag" "$sql_tag" <<'PY'
import json, pathlib, subprocess, sys
out, commit, runtime, server, sql = sys.argv[1:]
images = {}
for kind, tag in [('server', server), ('sql_tools', sql)]:
    inspect = json.loads(subprocess.check_output(['docker', 'image', 'inspect', tag], text=True))[0]
    if inspect['Config']['User'] != '1000:1000' or inspect['Os'] != 'linux' or inspect['Architecture'] != 'amd64':
        raise SystemExit('Incorrect image platform or runtime UID')
    if inspect['Config']['Labels']['org.opencontainers.image.revision'] != commit:
        raise SystemExit('Incorrect image source label')
    images[kind] = {'tag': tag, 'image_id': inspect['Id']}
metadata = {'schema_version': 1, 'source_commit': commit, 'runtime_base': runtime, 'images': images}
(pathlib.Path(out) / 'image-metadata.json').write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n')
print('LOCAL_IMAGES_OK commit=' + commit)
PY