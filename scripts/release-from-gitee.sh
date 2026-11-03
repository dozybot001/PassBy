#!/usr/bin/env bash
# Server controller, run as root by scripts/publish.sh. It fetches the exact
# commit from private Gitee with a project read-only deploy key and builds the
# release only from that checkout. Nothing is uploaded from the developer Mac.
set -Eeuo pipefail
# The body is a function so bash reads it completely from the SSH stdin before
# running, and no child process can consume the rest of the script.
main() {
    component="${1:-}"
    release="${2:-}"
    [[ "$component" =~ ^(site|auth)$ && "$release" =~ ^[0-9a-f]{40}$ ]] || { echo 'usage: site|auth <commit> <gitee-keys>' >&2; exit 2; }
    builder=/opt/passby-release/builder
    key="$builder/gitee_read_ed25519"
    hosts="$builder/gitee_known_hosts"
    source="$builder/source.git"
    node_image='docker.m.daocloud.io/library/node@sha256:235600a8101ab264e117b1768e925532262668dc9b581ef1dd7d96ced463b8e7'
    install -d -m 0750 /opt/passby-release "$builder"
    exec 9>/opt/passby-release/.controller-lock
    flock -n 9 || { echo 'Another PassBy release is running.' >&2; exit 1; }

    # Gitee host keys come from the repository's scripts/known_hosts, never a scan.
    printf '%s' "${3:-}" | base64 -d > "$hosts.candidate"
    [[ -s "$hosts.candidate" ]] && ! grep -qv '^gitee\.com ' "$hosts.candidate" || { echo 'Pinned Gitee host keys are missing.' >&2; exit 1; }
    mv "$hosts.candidate" "$hosts"
    if [[ ! -f "$key" ]]; then
        ssh-keygen -q -t ed25519 -N '' -C 'passby-server-gitee-read' -f "$key"
        chmod 0600 "$key"
        echo 'Created the server read-only key. Add this public key to Gitee dozybot/PassBy as a deploy key (pull only), then publish again:' >&2
        cat "$key.pub" >&2
        exit 3
    fi
    export GIT_SSH_COMMAND="ssh -i $key -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$hosts"
    [[ -d "$source" ]] || git clone -q --bare git@gitee.com:dozybot/PassBy.git "$source"
    # Bounded retries absorb short regional outages; failure stops before production changes.
    for attempt in 1 2 3 4; do
        git --git-dir="$source" fetch -q origin +refs/heads/main:refs/heads/main && break
        (( attempt < 4 )) || { echo 'Unable to fetch Gitee main.' >&2; exit 1; }
        sleep $(( attempt * 3 ))
    done
    fetched="$(git --git-dir="$source" rev-parse refs/heads/main)"
    [[ "$fetched" == "$release" ]] || { echo "Gitee main is $fetched, not the requested $release." >&2; exit 1; }

    stage="$(mktemp -d)"
    trap 'rm -rf "$stage"' EXIT
    git --git-dir="$source" archive "$release" public server scripts PassBy.xcodeproj/project.pbxproj | tar -x -C "$stage"
    # Housekeeping after an accepted release never fails it.
    retain() { python3 "$stage/scripts/retention.py" "$1" || echo 'Release retention skipped.' >&2; }
    if [[ "$component" == site ]]; then
        bash "$stage/scripts/release-site.sh" "$stage" "$release"
        retain site
        exit
    fi

    # Install the exact locked dependencies in the pinned runtime image, without host secrets.
    docker run --rm --cap-drop ALL --security-opt no-new-privileges \
        --mount "type=bind,src=$stage/server,dst=/app" --workdir /app --env npm_config_cache=/tmp/npm-cache \
        "$node_image" npm ci --ignore-scripts --no-audit --no-fund >/dev/null
    bundle="$stage/bundle"
    mkdir -p "$bundle/scripts"
    cp -R "$stage/server" "$bundle/server"
    cp "$stage/scripts/release-auth.py" "$bundle/scripts/"
    python3 - "$bundle" "$release" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1]); files = {}
for p in root.rglob('*'):
    if p.is_symlink() or p.suffix == '.node': raise SystemExit('Only regular portable dependencies are supported')
    if p.is_file(): files[str(p.relative_to(root))] = hashlib.sha256(p.read_bytes()).hexdigest()
(root / 'manifest.json').write_text(json.dumps({'commit': sys.argv[2], 'files': files}))
PY
    tar --no-xattrs -czf "/tmp/passby-auth-$release.tar.gz" -C "$bundle" server scripts manifest.json
    python3 "$stage/scripts/release-auth.py" "$release"
    rm -f "/tmp/passby-auth-$release.tar.gz"
    retain auth
}
main "$@" </dev/null
