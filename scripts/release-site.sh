#!/usr/bin/env bash
# Runs on the server from the exact Gitee export prepared by release-from-gitee.sh.
set -Eeuo pipefail
stage="$1"
release="$2"
[[ "$release" =~ ^[0-9a-f]{40}$ && -d "$stage/public" ]]
bundle="$stage/bundle"
mkdir "$bundle"
cp -R "$stage/public" "$bundle/public"
python3 - "$bundle" "$release" "$stage/PassBy.xcodeproj/project.pbxproj" <<'PY'
import hashlib, json, pathlib, sys, re
root = pathlib.Path(sys.argv[1])
project = pathlib.Path(sys.argv[3]).read_text()
version = re.search(r'"MARKETING_VERSION" = "([^";]+)";', project).group(1)
page = root / 'public/index.html'
page.write_text(page.read_text().replace('<title>', '<meta name="passby-version" content="' + version + ' · Web ' + sys.argv[2][:12] + '">\n  <title>', 1))
# Give the whole module graph and styles a fresh URL on each release.
# Versioning only app.mjs leaves imported modules reusable under old URLs.
asset_pattern = re.compile(r'([\'"])([^\'"\s<>]+\.(?:mjs|js|css|svg))(?:\?[^\'"\s<>]*)?([\'"])')
for asset in (root / 'public').rglob('*'):
    if asset.suffix not in ('.html', '.mjs'):
        continue
    def version_asset(match):
        quote, path, closing = match.groups()
        if quote != closing or path.startswith(('http:', 'https:', '//')):
            return match.group(0)
        return quote + path + '?v=' + sys.argv[2] + closing
    asset.write_text(asset_pattern.sub(version_asset, asset.read_text()))
files = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
         for p in sorted((root / 'public').rglob('*')) if p.is_file()}
(root / 'manifest.json').write_text(json.dumps({'commit': sys.argv[2], 'files': files}, indent=2))
PY
directory="/opt/passby-site/releases/$release"
config=/etc/caddy/sites-enabled/tenon-ai.caddy
web_config=/etc/caddy/sites-enabled/passby.caddy
lock=/opt/passby-site/.publish-lock
mkdir -p /opt/passby-site/releases
mkdir "$lock" || { echo 'PassBy site publication is already running.' >&2; exit 1; }
trap 'rmdir "$lock"' EXIT
if [[ ! -d "$directory" ]]; then
    cp -R "$bundle" "$directory"
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
if [[ -f "$web_config" ]]; then cp "$web_config" "$lock/web-before.caddy"; fi
python3 - "$config" "$lock/candidate.caddy" "$directory" "$lock/web-candidate.caddy" <<'PYROUTE'
import json,pathlib,re,sys
source=pathlib.Path(sys.argv[1]).read_text()
source=re.sub(r'\n\t# BEGIN PASSBY\n.*?\t# END PASSBY\n','\n',source,flags=re.S)
assert source.startswith('tenon.asia {\n')
auth_route=pathlib.Path('/opt/passby-auth/current-route.caddy').read_text()
legacy=('\t# BEGIN PASSBY\n'+auth_route+'\t@passby_legacy path /passby /passby/*\n'
        '\thandle @passby_legacy {\n\t\troute {\n\t\t\turi strip_prefix /passby\n'
        '\t\t\tredir https://passby.tenon.asia{uri} permanent\n\t\t}\n\t}\n\t# END PASSBY\n')
pathlib.Path(sys.argv[2]).write_text(source.replace('tenon.asia {\n','tenon.asia {\n'+legacy,1))
port=json.loads(pathlib.Path('/opt/passby-auth/active.json').read_text())['port']
assert port in (7280,7281)
web="""passby.tenon.asia {
    encode zstd gzip
    header {
        Cache-Control "no-store"
        Referrer-Policy "no-referrer"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Content-Security-Policy "frame-ancestors 'none'"
        Cross-Origin-Opener-Policy "same-origin-allow-popups"
        Permissions-Policy "camera=(), microphone=(), geolocation=(), clipboard-read=()"
    }
    handle /api/* {
        reverse_proxy 127.0.0.1:PORT
    }
    handle {
        root * DIRECTORY/public
        file_server
    }
}
""".replace('PORT',str(port)).replace('DIRECTORY',sys.argv[3])
pathlib.Path(sys.argv[4]).write_text(web)
PYROUTE
# Validate the candidate with all other current sites before touching ingress.
mkdir "$lock/sites"
cp /etc/caddy/sites-enabled/*.caddy "$lock/sites/"
cp "$lock/candidate.caddy" "$lock/sites/tenon-ai.caddy"
cp "$lock/web-candidate.caddy" "$lock/sites/passby.caddy"
printf 'import %s/sites/*.caddy\n' "$lock" > "$lock/Caddyfile"
caddy validate --config "$lock/Caddyfile" --adapter caddyfile >/dev/null
rollback() {
    cp "$lock/previous.caddy" "$config"
    if [[ -f "$lock/web-before.caddy" ]]; then cp "$lock/web-before.caddy" "$web_config"; else rm -f "$web_config"; fi
    systemctl reload caddy
}
cp "$lock/candidate.caddy" "$config"
cp "$lock/web-candidate.caddy" "$web_config"
if ! systemctl reload caddy; then rollback; exit 1; fi
if ! python3 - "$directory" <<'PY'
import hashlib, json, pathlib, sys, time, urllib.request
for attempt in range(6):
    try:
        urllib.request.urlopen('https://passby.tenon.asia/api/health',timeout=10)
        break
    except Exception:
        if attempt==5: raise
        time.sleep(3)
root = pathlib.Path(sys.argv[1])
for name, digest in json.loads((root / 'manifest.json').read_text())['files'].items():
    path = name.removeprefix('public/')
    if path.endswith('index.html'): path = path.removesuffix('index.html')
    response = urllib.request.urlopen('https://passby.tenon.asia/' + path, timeout=20)
    assert hashlib.sha256(response.read()).hexdigest() == digest, name
    if path == '':
        assert response.headers.get('X-Frame-Options') == 'DENY'
        assert 'no-store' in response.headers.get('Cache-Control', '')
        assert "frame-ancestors 'none'" in response.headers.get('Content-Security-Policy', '')
legacy=urllib.request.urlopen('https://tenon.asia/passby/',timeout=20)
assert legacy.url=='https://passby.tenon.asia/'
assert urllib.request.urlopen('https://tenon.asia/passby/api/health',timeout=20).status==200
PY
then
    rollback
    exit 1
fi
cp "$lock/previous.caddy" "$directory/ingress-before.caddy"
find "$directory" -type f -exec chmod 0444 {} +
ln -sfn "$directory" /opt/passby-site/current
printf '%s\n' "$release" > /opt/passby-site/last-successful-commit
rm -rf "$lock/sites" "$lock/Caddyfile" "$lock/candidate.caddy" "$lock/previous.caddy" "$lock/web-before.caddy" "$lock/web-candidate.caddy"
echo "Published PassBy web app, support and privacy pages: $release"
