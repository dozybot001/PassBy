#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit changes before publishing.' >&2; exit 1; }
release="$(git rev-parse HEAD)"
node --test scripts/test-web.mjs
for module in public/web/*.mjs; do node --check "$module"; done
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
COPYFILE_DISABLE=1 tar --no-xattrs -czf "$staging/site.tar.gz" -C "$staging" public manifest.json
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
route = ('\t# BEGIN PASSBY\n\tredir /passby /passby/ permanent\n\thandle_path /passby/* {\n'
         '\t\theader {\n\t\t\tCache-Control "no-store"\n\t\t\tReferrer-Policy "no-referrer"\n'
         '\t\t\tX-Frame-Options "DENY"\n\t\t\tContent-Security-Policy "frame-ancestors \'none\'"\n'
         '\t\t\tCross-Origin-Opener-Policy "same-origin-allow-popups"\n'
         '\t\t\tPermissions-Policy "camera=(), microphone=(), geolocation=(), clipboard-read=()"\n\t\t}\n'
         '\t\troot * ' + sys.argv[3] + '/public\n\t\tfile_server\n\t}\n\t# END PASSBY\n')
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
if ! python3 - "$directory" <<'PY'
import hashlib, json, pathlib, sys, urllib.request
root = pathlib.Path(sys.argv[1])
for name, digest in json.loads((root / 'manifest.json').read_text())['files'].items():
    path = name.removeprefix('public/')
    if path.endswith('index.html'): path = path.removesuffix('index.html')
    response = urllib.request.urlopen('https://tenon.asia/passby/' + path, timeout=20)
    assert hashlib.sha256(response.read()).hexdigest() == digest, name
    if path == '':
        assert response.headers.get('X-Frame-Options') == 'DENY'
        assert 'no-store' in response.headers.get('Cache-Control', '')
        assert "frame-ancestors 'none'" in response.headers.get('Content-Security-Policy', '')
PY
then
    rollback
    exit 1
fi
cp "$lock/previous.caddy" "$directory/ingress-before.caddy"
find "$directory" -type f -exec chmod 0444 {} +
ln -sfn "$directory" /opt/passby-site/current
printf '%s\n' "$release" > /opt/passby-site/last-successful-commit
rm -f "$incoming"
rm -rf "$lock/sites" "$lock/Caddyfile" "$lock/candidate.caddy" "$lock/previous.caddy"
echo "Published PassBy web app, support and privacy pages: $release"
REMOTE
