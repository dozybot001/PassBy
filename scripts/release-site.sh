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
# Hosts served by passby.caddy; the first is canonical.
web_hosts='passby.tenonai.cn'
# Hosts that only redirect to the canonical host: pages 301, /api/* 308, so no
# request reaches the backend. PassBy's switch moves passby.tenon.asia here.
moved_hosts='passby.tenon.asia'
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
python3 - "$config" "$lock/candidate.caddy" "$directory" "$lock/web-candidate.caddy" "$web_hosts" "$moved_hosts" <<'PYROUTE'
import json,pathlib,re,sys
source=pathlib.Path(sys.argv[1]).read_text()
source=re.sub(r'\n\t# BEGIN PASSBY\n.*?\t# END PASSBY\n','\n',source,flags=re.S)
# The main site may list tenonai.cn beside tenon.asia; PassBy's block goes into
# that one site. Its handles outrank a main-site catch-all handle redirect.
address=re.findall(r'^(?:[\w.-]+, )*tenon\.asia(?:, [\w.-]+)* \{\n',source,flags=re.M)
assert len(address)==1,'Expected one tenon.asia site block'
# The identity service was retired on 2026-11-15: every old API path answers 410
# so that old apps stop retrying, and nothing is proxied to a backend.
gone='{"type":"about:blank","title":"Gone","status":410,"detail":"PassBy sign-in and sync were retired on 2026-11-15."}'
auth_route=('\thandle /passby/api/* {\n\t\theader Cache-Control "no-store"\n'
            '\t\theader Content-Type application/problem+json\n\t\trespond `'+gone+'` 410\n\t}\n')
hosts,moved=sys.argv[5].split(),sys.argv[6].split()
assert hosts and all(re.fullmatch(r'passby\.tenon(?:\.asia|ai\.cn)',host) for host in hosts+moved) and not set(hosts)&set(moved)
legacy=('\t# BEGIN PASSBY\n'+auth_route+'\t@passby_legacy path /passby /passby/*\n'
        '\thandle @passby_legacy {\n\t\troute {\n\t\t\turi strip_prefix /passby\n'
        '\t\t\tredir https://'+hosts[0]+'{uri} permanent\n\t\t}\n\t}\n\t# END PASSBY\n')
pathlib.Path(sys.argv[2]).write_text(source.replace(address[0],address[0]+legacy,1))
web="""HOSTS {
    import access_log
    encode zstd gzip
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        Cache-Control "no-store"
        Referrer-Policy "no-referrer"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Permissions-Policy "camera=(), microphone=(), geolocation=(), clipboard-read=()"
    }
    # The sync page (/app/) holds a whole notebook in memory, so it gets its own, stricter policy:
    # only this site's scripts and styles, and connections to plain http only, which the page then
    # narrows to the one phone the person entered (docs/sync.md 7). Every other page keeps the
    # policy it had. The two blocks never both apply.
    @app path /app /app/*
    header @app {
        Content-Security-Policy "APP_CSP"
        Cross-Origin-Opener-Policy "same-origin"
        Cross-Origin-Resource-Policy "same-origin"
    }
    @pages not path /app /app/*
    header @pages {
        Content-Security-Policy "PAGES_CSP"
        Cross-Origin-Opener-Policy "same-origin-allow-popups"
    }
    @api path /api/* /passby/api/*
    handle @api {
        header Content-Type application/problem+json
        respond `GONE` 410
    }
    handle {
        root * DIRECTORY/public
        file_server
    }
    handle_errors {
        root * DIRECTORY/public
        @missing expression `{err.status_code} == 404`
        rewrite @missing /404.html
        @down expression `{err.status_code} in [502, 503, 504]`
        rewrite @down /maintenance.html
        rewrite * /500.html
        file_server
    }
}
""".replace('GONE',gone).replace('HOSTS',', '.join(hosts)).replace('DIRECTORY',sys.argv[3]).replace('PAGES_CSP',
    "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; "
    "base-uri 'none'; form-action 'none'; frame-ancestors 'none'").replace('APP_CSP',
    "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src http:; "
    "base-uri 'none'; form-action 'none'; frame-ancestors 'none'; require-trusted-types-for 'script'")
for host in moved:
    web+=f"""{host} {{
    import access_log
    header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    handle /api/* {{
        redir https://{hosts[0]}{{uri}} 308
    }}
    handle {{
        redir https://{hosts[0]}{{uri}} permanent
    }}
}}
"""
pathlib.Path(sys.argv[4]).write_text(web)
PYROUTE
# Validate the candidate with all other current sites before touching ingress.
mkdir "$lock/sites"
cp /etc/caddy/sites-enabled/*.caddy "$lock/sites/"
cp "$lock/candidate.caddy" "$lock/sites/tenon-ai.caddy"
cp "$lock/web-candidate.caddy" "$lock/sites/passby.caddy"
# The root config defines shared snippets such as access_log; validate through it.
python3 - "$lock" <<'PY'
import pathlib, sys
line = 'import /etc/caddy/sites-enabled/*.caddy'
root = pathlib.Path('/etc/caddy/Caddyfile').read_text()
assert root.count(line) == 1, 'Unexpected Caddy root config'
pathlib.Path(sys.argv[1], 'Caddyfile').write_text(root.replace(line, 'import ' + sys.argv[1] + '/sites/*.caddy'))
PY
caddy validate --config "$lock/Caddyfile" --adapter caddyfile >/dev/null
rollback() {
    cp "$lock/previous.caddy" "$config"
    if [[ -f "$lock/web-before.caddy" ]]; then cp "$lock/web-before.caddy" "$web_config"; else rm -f "$web_config"; fi
    systemctl reload caddy
}
cp "$lock/candidate.caddy" "$config"
cp "$lock/web-candidate.caddy" "$web_config"
if ! systemctl reload caddy; then rollback; exit 1; fi
if ! python3 - "$directory" "$web_hosts" "$moved_hosts" <<'PY'
import hashlib, json, pathlib, sys, time, urllib.error, urllib.request
hsts = 'max-age=31536000; includeSubDomains'
hosts, moved = sys.argv[2].split(), sys.argv[3].split()
def gone(url):
    try:
        urllib.request.urlopen(url, timeout=20)
    except urllib.error.HTTPError as error:
        return error.code == 410 and 'problem+json' in error.headers.get('Content-Type', '')
    return False
class Stay(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args): return None
for host in moved:
    for path, code in (('/support/?lang=zh', 301), ('/api/health', 308)):
        try:
            urllib.request.build_opener(Stay).open(f'https://{host}{path}', timeout=20)
            raise AssertionError(f'{host} must redirect')
        except urllib.error.HTTPError as moving:
            assert moving.code == code and moving.headers['Location'] == f'https://{hosts[0]}{path}', host
for host in hosts:
    # A newly added host waits for Caddy to obtain its first certificate.
    tries = 6 if host == 'passby.tenon.asia' else 60
    for attempt in range(tries):
        try:
            home = urllib.request.urlopen(f'https://{host}/',timeout=10)
            break
        except Exception:
            if attempt==tries-1: raise
            time.sleep(3)
    assert home.headers.get('Strict-Transport-Security') == hsts
    for path in ('/api/health', '/api/auth/start', '/passby/api/health'):
        assert gone(f'https://{host}{path}'), path
    assert home.headers.get('X-Frame-Options') == 'DENY'
    footer = home.read().decode()
    assert '湘ICP备2026054319号-1' in footer and '湘公网安备' not in footer, host
root = pathlib.Path(sys.argv[1])
for name, digest in json.loads((root / 'manifest.json').read_text())['files'].items():
    path = name.split('/', 1)[1]
    host = hosts[0]
    if path.endswith('index.html'): path = path.removesuffix('index.html')
    response = urllib.request.urlopen(f'https://{host}/' + path, timeout=20)
    assert hashlib.sha256(response.read()).hexdigest() == digest, name
    if path == '':
        assert response.headers.get('Strict-Transport-Security') == hsts
        assert response.headers.get('X-Frame-Options') == 'DENY'
        assert 'no-store' in response.headers.get('Cache-Control', '')
        pages = response.headers.get('Content-Security-Policy', '')
        assert "default-src 'none'" in pages and "frame-ancestors 'none'" in pages and 'connect-src' not in pages, pages
        assert response.headers.get('Cross-Origin-Opener-Policy') == 'same-origin-allow-popups'
    if path.startswith('app/'):
        policy = response.headers.get('Content-Security-Policy', '')
        assert "default-src 'none'" in policy and "script-src 'self'" in policy and "connect-src http:;" in policy, policy
        assert "require-trusted-types-for 'script'" in policy and "frame-ancestors 'none'" in policy, policy
        assert response.headers.get('Cross-Origin-Opener-Policy') == 'same-origin'
        assert response.headers.get('Cross-Origin-Resource-Policy') == 'same-origin'
        assert response.headers.get('Referrer-Policy') == 'no-referrer'
        assert 'no-store' in response.headers.get('Cache-Control', '')
try:
    urllib.request.urlopen(f'https://{hosts[0]}/release-check-missing',timeout=20)
    raise AssertionError('A missing page must return 404')
except urllib.error.HTTPError as missing:
    assert missing.code == 404 and b'Page not found' in missing.read()
legacy=urllib.request.urlopen('https://tenon.asia/passby/',timeout=20)
assert legacy.url==f'https://{hosts[0]}/'
assert gone('https://tenon.asia/passby/api/health')
PY
then
    rollback
    exit 1
fi
cp "$lock/previous.caddy" "$directory/ingress-before.caddy"
find "$directory" -type f -exec chmod 0444 {} +
# Retention keeps the release this one replaced.
if [[ -L /opt/passby-site/current && "$(readlink /opt/passby-site/current)" != "$directory" ]]; then
    ln -sfn "$(readlink /opt/passby-site/current)" /opt/passby-site/previous
fi
ln -sfn "$directory" /opt/passby-site/current
printf '%s\n' "$release" > /opt/passby-site/last-successful-commit
rm -rf "$lock/sites" "$lock/Caddyfile" "$lock/candidate.caddy" "$lock/previous.caddy" "$lock/web-before.caddy" "$lock/web-candidate.caddy"
echo "Published PassBy introduction, support and legal pages: $release"
