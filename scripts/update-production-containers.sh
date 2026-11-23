#!/usr/bin/env bash
# SHUOMI-ERP PRIVATE CUSTOMIZATION: production/local deployment
# Update an existing 1Panel ERP stack from a verified update-image bundle.
# Usage: bash scripts/update-production-containers.sh /absolute/release/dir [absolute/app/dir]
set -Eeuo pipefail
umask 077
TaskDefaultAppDir=/model/1Panel/1panel/docker/compose/shuomi-erp
TaskWaitTimeout=300
TaskChanged=0
TaskBackupDir=''
TaskTempDir=''
TaskCleanup() { [[ -z $TaskTempDir ]] || rm -rf -- "$TaskTempDir"; }
trap TaskCleanup EXIT
TaskEnvUnsetArgs=(-u DOCKER_CONTEXT -u DOCKER_HOST -u IMAGE_TAG -u IMAGE_PREFIX)
TaskUsage() {
    printf 'Usage: %s /absolute/update-release/dir [absolute/app/dir]\n' "$0" >&2
    printf 'The app directory must contain compose.yaml and the authoritative .env.\n' >&2
    exit 2
}
[[ $# -ge 1 && $# -le 2 ]] || TaskUsage
[[ $1 == /* && ${2:-$TaskDefaultAppDir} == /* ]] || TaskUsage
for TaskDependency in python3 docker flock realpath mktemp cp env grep sort chmod date mkdir rm; do
    command -v "$TaskDependency" >/dev/null || { printf 'Required command is missing: %s\n' "$TaskDependency" >&2; exit 2; }
done
TaskReleaseDir=$(realpath -e -- "$1")
TaskAppDir=$(realpath -e -- "${2:-$TaskDefaultAppDir}")
TaskEnvFile=$TaskAppDir/.env
TaskComposeFile=$TaskAppDir/compose.yaml
[[ -d $TaskReleaseDir && -d $TaskAppDir && -f $TaskEnvFile && ! -L $TaskEnvFile && -f $TaskComposeFile && ! -L $TaskComposeFile ]] || {
    printf 'Expected a release directory and an existing stack with compose.yaml and a regular .env file.\n' >&2
    exit 2
}
exec 9>"$TaskAppDir/.shuomi-erp-update.lock"
flock -n 9 || { printf 'Another ERP update is already running.\n' >&2; exit 2; }
TaskDocker=(env -u DOCKER_CONTEXT -u DOCKER_HOST docker --host unix:///var/run/docker.sock)
"${TaskDocker[@]}" info >/dev/null
"${TaskDocker[@]}" compose version >/dev/null
TaskCompose() {
    env "${TaskEnvUnsetArgs[@]}" docker --host unix:///var/run/docker.sock compose \
        --project-name shuomi-erp --env-file "$TaskEnvFile" --file "$TaskComposeFile" "$@"
}
TaskRollback() {
    TaskExit=$?
    trap - ERR
    set +e
    if [[ $TaskChanged == 1 ]]; then
        printf 'Update failed; restoring the previous environment and Compose from %s\n' "$TaskBackupDir" >&2
        cp -p -- "$TaskBackupDir/.env" "$TaskEnvFile"
        TaskEnvRestore=$?
        cp -p -- "$TaskBackupDir/compose.yaml" "$TaskComposeFile"
        TaskComposeRestore=$?
        if [[ $TaskEnvRestore == 0 && $TaskComposeRestore == 0 ]] && TaskCompose config --quiet && \
            TaskCompose up --detach --no-deps --no-build --pull never --wait --wait-timeout "$TaskWaitTimeout" backend web; then
            printf 'Previous application version restored and healthy. Backup: %s\n' "$TaskBackupDir" >&2
        else
            printf 'Automatic rollback could not restore a healthy stack. Inspect the stack and use backup %s\n' "$TaskBackupDir" >&2
        fi
    elif [[ $BASH_SUBSHELL == 0 ]]; then
        printf 'Update stopped before changing the stack configuration.\n' >&2
    fi
    exit "${TaskExit:-1}"
}
trap TaskRollback ERR
# Clear shell overrides for keys present in .env so 1Panel's file is authoritative.
while IFS= read -r TaskEnvKey; do TaskEnvUnsetArgs+=(-u "$TaskEnvKey"); done < <(python3 - "$TaskEnvFile" <<'PY'
import re, sys
with open(sys.argv[1], encoding='utf-8-sig') as stream:
    for line in stream:
        match = re.match(r'^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=', line)
        if match:
            print(match.group(1))
PY
)
# Confirm the existing stack can be re-created locally before applying a release.
TaskCompose config --quiet
TaskPreviousImages=$(TaskCompose config --images)
while IFS= read -r TaskPreviousImage; do
    [[ -n $TaskPreviousImage ]] && "${TaskDocker[@]}" image inspect "$TaskPreviousImage" >/dev/null
done <<< "$TaskPreviousImages"
printf 'Checking release checksums and manifest...\n'
TaskMetadata=$(python3 - "$TaskReleaseDir" <<'PY'
import hashlib, json, os, re, sys
release = os.path.realpath(sys.argv[1])
def fail(message):
    raise SystemExit(message)
def safe_file(name):
    if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9._/-]+', name) or name.startswith('/') or '..' in name.split('/'):
        fail('Unsafe release filename.')
    target = os.path.realpath(os.path.join(release, name))
    if os.path.commonpath([release, target]) != release or not os.path.isfile(target):
        fail('Missing or out-of-directory release file: ' + name)
    return target
checksums = {}
with open(safe_file('SHA256SUMS'), encoding='utf-8-sig') as stream:
    for line in stream:
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9._/-]+)\r?\n?', line)
        if not match or match.group(2) in checksums:
            fail('Malformed or duplicate SHA256SUMS entry.')
        checksums[match.group(2)] = match.group(1)
for required in ('images.tar.gz', 'images.json', 'docker/docker-compose.prod.yml'):
    if required not in checksums:
        fail('Missing required checksum: ' + required)
for name, expected in checksums.items():
    digest = hashlib.sha256()
    with open(safe_file(name), 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        fail('Checksum mismatch: ' + name)
with open(safe_file('images.json'), encoding='utf-8-sig') as stream:
    manifest = json.load(stream)
if manifest.get('SchemaVersion') != 1 or manifest.get('Project') != 'shuomi-erp' or manifest.get('PackageType') != 'update':
    fail('This updater accepts ERP update packages only; first deployment is a separate procedure.')
tag, prefix = manifest.get('ReleaseTag', ''), manifest.get('ImagePrefix', '')
if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}', tag):
    fail('Invalid release tag.')
if not re.fullmatch(r'[a-z0-9][a-z0-9._/-]*(?::[0-9]+)?(?:/[a-z0-9][a-z0-9._/-]*)?', prefix):
    fail('Invalid image prefix.')
if manifest.get('Archive') != 'images.tar.gz' or manifest.get('ArchiveSha256') != checksums['images.tar.gz']:
    fail('Archive metadata does not match the checked archive.')
images = manifest.get('Images')
if not isinstance(images, list) or len(images) != 2 or {image.get('Role') for image in images if isinstance(image, dict)} != {'backend', 'web'}:
    fail('The update manifest must contain exactly backend and web images.')
by_role = {image['Role']: image for image in images}
for role in ('backend', 'web'):
    image = by_role[role]
    if image.get('Name') != prefix + '-' + role + ':' + tag or image.get('Platform') != 'linux/amd64' or not re.fullmatch(r'sha256:[0-9a-f]{64}', image.get('Id', '')):
        fail('Invalid image metadata for ' + role)
print(tag)
print(prefix)
for role in ('backend', 'web'):
    print(by_role[role]['Name'])
    print(by_role[role]['Id'])
print('Verified ' + str(len(checksums)) + ' release checksums.', file=sys.stderr)
PY
)
mapfile -t TaskValues <<< "$TaskMetadata"
[[ ${#TaskValues[@]} == 6 ]] || { printf 'Unexpected release metadata.\n' >&2; false; }
TaskTag=${TaskValues[0]}
TaskBackendImage=${TaskValues[2]}
TaskBackendId=${TaskValues[3]}
TaskWebImage=${TaskValues[4]}
TaskWebId=${TaskValues[5]}
# Immutable release tags must never replace a previously loaded different image.
for TaskRole in backend web; do
    if [[ $TaskRole == backend ]]; then TaskImage=$TaskBackendImage; TaskExpectedId=$TaskBackendId
    else TaskImage=$TaskWebImage; TaskExpectedId=$TaskWebId; fi
    if TaskExistingId=$("${TaskDocker[@]}" image inspect --format '{{.Id}}' "$TaskImage" 2>/dev/null); then
        [[ $TaskExistingId == "$TaskExpectedId" ]] || { printf 'Release tag already points to another image: %s\n' "$TaskImage" >&2; false; }
    fi
done
# Compare privately rendered configuration before changing the authoritative files.
TaskTempDir=$(mktemp -d "$TaskAppDir/.update-check-XXXXXX")
cp -- "$TaskEnvFile" "$TaskTempDir/.env"
python3 - "$TaskTempDir/.env" "$TaskTag" <<'PY'
import os, re, stat, sys, tempfile
filename, tag = sys.argv[1:]
with open(filename, encoding='utf-8-sig', newline='') as stream:
    content = stream.read()
pattern = re.compile(r'(?m)^\s*(?:export\s+)?IMAGE_TAG\s*=.*$')
if len(pattern.findall(content)) > 1:
    raise SystemExit('Duplicate IMAGE_TAG entries in the production environment.')
if pattern.search(content):
    content = pattern.sub('IMAGE_TAG=' + tag, content)
else:
    content = content.rstrip('\r\n') + '\nIMAGE_TAG=' + tag + '\n'
mode = stat.S_IMODE(os.stat(filename).st_mode)
fd, temporary = tempfile.mkstemp(prefix='.env.update-', dir=os.path.dirname(filename))
try:
    os.fchmod(fd, mode)
    with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
        stream.write(content.replace('\r\n', '\n'))
    os.replace(temporary, filename)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY
TaskCompose config --format json > "$TaskTempDir/old.json"
env "${TaskEnvUnsetArgs[@]}" docker --host unix:///var/run/docker.sock compose \
    --project-name shuomi-erp --env-file "$TaskTempDir/.env" --file "$TaskReleaseDir/docker/docker-compose.prod.yml" \
    config --format json > "$TaskTempDir/new.json"
python3 - "$TaskTempDir/old.json" "$TaskTempDir/new.json" "$TaskBackendImage" "$TaskWebImage" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    old = json.load(stream)
with open(sys.argv[2]) as stream:
    new = json.load(stream)
changed = []
if set(old.get('services', {})) != {'backend', 'web', 'redis'} or set(new.get('services', {})) != {'backend', 'web', 'redis'}:
    changed.append('services')
for field in ('volumes', 'networks'):
    if old.get(field, {}) != new.get(field, {}):
        changed.append(field)
for role in ('backend', 'web'):
    for field in ('volumes', 'networks'):
        if old.get('services', {}).get(role, {}).get(field, {}) != new.get('services', {}).get(role, {}).get(field, {}):
            changed.append('services.' + role + '.' + field)
if old.get('services', {}).get('redis') != new.get('services', {}).get('redis'):
    changed.append('services.redis')
for role, image in zip(('backend', 'web'), sys.argv[3:]):
    if new.get('services', {}).get(role, {}).get('image') != image:
        changed.append('services.' + role + '.image')
if changed:
    raise SystemExit('This release requires a separately reviewed infrastructure change: ' + ', '.join(changed))
PY

printf 'Loading the checked archive for release %s...\n' "$TaskTag"
"${TaskDocker[@]}" load --input "$TaskReleaseDir/images.tar.gz"
for TaskRole in backend web; do
    if [[ $TaskRole == backend ]]; then TaskImage=$TaskBackendImage; TaskExpectedId=$TaskBackendId
    else TaskImage=$TaskWebImage; TaskExpectedId=$TaskWebId; fi
    TaskActual=$("${TaskDocker[@]}" image inspect --format '{{.Id}} {{.Os}}/{{.Architecture}}' "$TaskImage")
    [[ $TaskActual == "$TaskExpectedId linux/amd64" ]] || { printf 'Loaded image ID/platform mismatch: %s\n' "$TaskImage" >&2; false; }
done
mkdir -p -- "$TaskAppDir/backups"
TaskBackupDir=$(mktemp -d "$TaskAppDir/backups/$(date +%Y%m%d-%H%M%S)-XXXXXX")
cp -p -- "$TaskEnvFile" "$TaskBackupDir/.env"
cp -p -- "$TaskComposeFile" "$TaskBackupDir/compose.yaml"
chmod 600 -- "$TaskBackupDir/.env"
TaskChanged=1
cp -- "$TaskReleaseDir/docker/docker-compose.prod.yml" "$TaskComposeFile"
cp -- "$TaskTempDir/.env" "$TaskEnvFile"
chmod 600 -- "$TaskEnvFile"
TaskCompose config --quiet
TaskServices=$(TaskCompose config --services | LC_ALL=C sort)
[[ $TaskServices == $'backend\nredis\nweb' ]] || { printf 'Production Compose must contain only backend, redis and web.\n' >&2; false; }
TaskConfiguredImages=$(TaskCompose config --images)
grep -Fxq -- "$TaskBackendImage" <<< "$TaskConfiguredImages" && grep -Fxq -- "$TaskWebImage" <<< "$TaskConfiguredImages" || {
    printf 'The authoritative .env and Compose do not select this release. Check IMAGE_PREFIX.\n' >&2
    false
}
printf 'Recreating application services; persistent data volumes are retained...\n'
TaskCompose up --detach --no-deps --no-build --pull never --wait --wait-timeout "$TaskWaitTimeout" backend web
TaskCompose ps
TaskChanged=0
trap - ERR
printf 'Updated to %s and passed container health checks. Previous configuration: %s\n' "$TaskTag" "$TaskBackupDir"
printf 'Verify HTTPS login and business pages at https://erp.shuomishengda.cn before removing old release images.\n'
