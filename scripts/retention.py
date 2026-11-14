"""Keep the current and previous PassBy site releases plus the newest three on the server.

Run as root by release-from-gitee.sh after an accepted release; an older commit is
rebuilt from Gitee.
"""
import pathlib, re, shutil

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


if __name__ == '__main__':
    print('Old PassBy site releases removed:', ', '.join(f'{count} {kind}' for kind, count in site().items()))
