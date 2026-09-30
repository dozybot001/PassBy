#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit changes before publishing.' >&2; exit 1; }
release="$(git rev-parse HEAD)"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
git archive "$release" public | tar -x -C "$staging"
python3 - "$staging" "$release" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
         for p in sorted((root / 'public').rglob('*')) if p.is_file()}
(root / 'manifest.json').write_text(json.dumps({'commit': sys.argv[2], 'files': files}, indent=2))
PY
tar -czf "$staging/site.tar.gz" -C "$staging" public manifest.json
incoming="/tmp/passby-site-$release.tar.gz"
scp -q "$staging/site.tar.gz" "wesaid-prod:$incoming"
ssh -o BatchMode=yes wesaid-prod sudo -n bash -s -- "$release" "$incoming" <<'REMOTE'
set -Eeuo pipefail
release="$1"
incoming="$2"
[[ "$release" =~ ^[0-9a-f]{40}$ ]]
directory="/opt/passby-site/releases/$release"
config=/etc/caddy/sites-enabled/tenon-ai.caddy
lock=/opt/passby-site/.publish-lock
mkdir -p /opt/passby-site/releases
mkdir "$lock" || { echo 'PassBy site publication is already running.' >&2; exit 1; }
trap 'rmdir "$lock"' EXIT
if [[ ! -d "$directory" ]]; then
    mkdir "$directory"
    tar -xzf "$incoming" -C "$directory"
fi
python3 - "$directory" "$release" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
m = json.loads((root / 'manifest.json').read_text())
assert m['commit'] == sys.argv[2]
actual = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in (root / 'public').rglob('*') if p.is_file()}
assert actual == m['files']
PY
chmod -R a+rX "$directory"
cp "$config" "$lock/previous.caddy"
python3 - "$config" "$lock/candidate.caddy" "$directory" <<'PY'
import pathlib, re, sys
source = pathlib.Path(sys.argv[1]).read_text()
source = re.sub(r'\n\t# BEGIN PASSBY\n.*?\t# END PASSBY\n', '\n', source, flags=re.S)
assert source.startswith('tenon.asia {\n')
route = '\t# BEGIN PASSBY\n\thandle_path /passby/* {\n\t\troot * ' + sys.argv[3] + '/public\n\t\tfile_server\n\t}\n\t# END PASSBY\n'
pathlib.Path(sys.argv[2]).write_text(source.replace('tenon.asia {\n', 'tenon.asia {\n' + route, 1))
PY
# Validate the candidate with all other current sites before touching ingress.
mkdir "$lock/sites"
cp /etc/caddy/sites-enabled/*.caddy "$lock/sites/"
cp "$lock/candidate.caddy" "$lock/sites/tenon-ai.caddy"
printf 'import %s/sites/*.caddy\n' "$lock" > "$lock/Caddyfile"
caddy validate --config "$lock/Caddyfile" --adapter caddyfile >/dev/null
rollback() {
    cp "$lock/previous.caddy" "$config"
    systemctl reload caddy
}
cp "$lock/candidate.caddy" "$config"
if ! systemctl reload caddy; then rollback; exit 1; fi
if ! curl --fail --silent --show-error --max-time 20 https://tenon.asia/passby/privacy/ | cmp - "$directory/public/privacy/index.html" \
 || ! curl --fail --silent --show-error --max-time 20 https://tenon.asia/passby/support/ | cmp - "$directory/public/support/index.html"; then
    rollback
    exit 1
fi
cp "$lock/previous.caddy" "$directory/ingress-before.caddy"
ln -sfn "$directory" /opt/passby-site/current
printf '%s\n' "$release" > /opt/passby-site/last-successful-commit
rm -f "$incoming"
rm -rf "$lock/sites" "$lock/Caddyfile" "$lock/candidate.caddy" "$lock/previous.caddy"
echo "Published PassBy support and privacy pages: $release"
REMOTE
