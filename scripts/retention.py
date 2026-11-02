"""Keep the current and previous PassBy releases plus the newest three on the server.

Run as root by release-from-gitee.sh after an accepted release. Older releases go
with their stopped identity containers; an older commit is rebuilt from Gitee.
"""
import json, pathlib, re, shutil, subprocess, sys

KEEP = 3
COMMIT = re.compile('[0-9a-f]{40}')


def prune(releases, kept, keep=KEEP):
    """Remove commit directories outside `kept` and the newest `keep`; return the survivors and the count removed."""
    found = sorted((path for path in releases.iterdir() if path.is_dir() and not path.is_symlink() and COMMIT.fullmatch(path.name)),
                   key=lambda path: path.stat().st_mtime, reverse=True)
    survivors = {path.name for path in found[:keep]} | kept
    removed = [path for path in found if path.name not in survivors]
    for path in removed:
        shutil.rmtree(path)
    return survivors, len(removed)


def site(root=pathlib.Path('/opt/passby-site'), caddy=pathlib.Path('/etc/caddy/sites-enabled')):
    # Besides current and previous, keep any release a Caddy file still serves:
    # the Tenon site publisher verifies the PassBy root it finds there.
    kept = {link.resolve().name for link in (root / 'current', root / 'previous') if link.is_symlink()}
    served = re.compile(re.escape(str(root / 'releases')) + '/([0-9a-f]{40})')
    for config in caddy.glob('*.caddy'):
        kept |= set(served.findall(config.read_text()))
    return {'releases': prune(root / 'releases', kept)[1]}


def auth(base=pathlib.Path('/opt/passby-auth'), run=subprocess.run):
    state = json.loads((base / 'active.json').read_text())
    listing = run(['docker', 'ps', '--all', '--filter', 'name=passby-auth-', '--format', '{{.Names}}\t{{.State}}'],
                  check=True, capture_output=True, text=True).stdout
    slots = [(match.group(0), match.group(1), status) for name, status in (line.split('\t') for line in listing.splitlines())
             if (match := re.fullmatch(r'passby-auth-([0-9a-f]{12})-728[01]', name))]
    running = {prefix for _, prefix, status in slots if status == 'running'}
    kept = {commit for commit in (state['commit'], state.get('previous')) if commit}
    kept |= {path.name for path in (base / 'releases').iterdir() if path.name[:12] in running}
    survivors, releases = prune(base / 'releases', kept)
    stopped = [name for name, prefix, status in slots
               if status != 'running' and not any(commit.startswith(prefix) for commit in survivors)]
    for name in stopped:
        run(['docker', 'rm', name], check=True, stdout=subprocess.DEVNULL)
    # Every slot runs the one pinned Node image the live slot uses, so no image is removed.
    return {'releases': releases, 'containers': len(stopped)}


if __name__ == '__main__':
    component = sys.argv[1] if len(sys.argv) == 2 else ''
    if component not in ('site', 'auth'):
        sys.exit('usage: retention.py site|auth')
    result = site() if component == 'site' else auth()
    print('Old PassBy ' + component + ' releases removed:', ', '.join(f'{count} {kind}' for kind, count in result.items()))
