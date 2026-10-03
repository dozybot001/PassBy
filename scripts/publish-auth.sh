#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
[ -z "$(git status --porcelain)" ] || { echo 'Commit the complete release before publishing.' >&2; exit 1; }
release=$(git rev-parse HEAD)
npm test --prefix server
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
git archive "$release" server scripts/release-auth.py | tar -x -C "$stage"
npm ci --prefix "$stage/server" --offline --ignore-scripts --no-audit --no-fund
python3 - "$stage" "$release" <<'PY'
import pathlib,sys,hashlib,json
root=pathlib.Path(sys.argv[1]); files={}
for p in root.rglob('*'):
 if p.is_symlink() or p.suffix=='.node':raise SystemExit('Only regular portable dependencies are supported')
 if p.is_file():files[str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
(root/'manifest.json').write_text(json.dumps({'commit':sys.argv[2],'files':files}))
PY
tar -czf "$stage/bundle.tar.gz" -C "$stage" server scripts manifest.json
scp -q "$stage/bundle.tar.gz" "wesaid-prod:/tmp/passby-auth-$release.tar.gz"
ssh wesaid-prod "sudo python3 /dev/stdin '$release'" < scripts/release-auth.py
