"""Isolated checks for server release retention; never touches a real server or Docker."""
import json, os, pathlib, sys, tempfile, unittest
from types import SimpleNamespace

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import retention


def releases(root, count):
    commits = [format(n, 'x') * 40 for n in range(count)]  # newest first, distinct slot prefixes
    for age, commit in enumerate(commits):
        (root / 'releases' / commit / 'public').mkdir(parents=True)
        os.utime(root / 'releases' / commit, (1e9 - age, 1e9 - age))
    (root / 'releases' / 'not-a-commit').mkdir()
    return commits


class SiteRetention(unittest.TestCase):
    def test_keeps_current_previous_served_and_newest_three(self):
        with tempfile.TemporaryDirectory() as directory:
            root, caddy = pathlib.Path(directory) / 'site', pathlib.Path(directory) / 'caddy'
            caddy.mkdir(parents=True)
            commits = releases(root, 9)
            (root / 'current').symlink_to(root / 'releases' / commits[5])
            (root / 'previous').symlink_to(root / 'releases' / commits[6])
            (caddy / 'passby.caddy').write_text(f'root * {root}/releases/{commits[7]}/public\n')
            self.assertEqual(retention.site(root, caddy), {'releases': 3})
            self.assertEqual(sorted(path.name for path in (root / 'releases').iterdir()),
                             sorted(['not-a-commit', *commits[:3], *commits[5:8]]))


class AuthRetention(unittest.TestCase):
    def test_old_releases_go_with_stopped_slots_and_running_ones_stay(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            commits = releases(base, 8)
            (base / 'active.json').write_text(json.dumps({'commit': commits[0], 'previous': commits[6]}))
            # The newest slot runs; an unexpected older running slot also stays.
            slots = [(commits[0], 7280, 'running'), (commits[1], 7281, 'exited'), (commits[4], 7280, 'exited'),
                     (commits[5], 7281, 'running'), (commits[6], 7281, 'exited'), (commits[7], 7280, 'created')]
            listing = ''.join(f'passby-auth-{commit[:12]}-{port}\t{status}\n' for commit, port, status in slots) + 'unrelated\texited\n'
            commands = []
            def run(args, **options):
                commands.append(args)
                return SimpleNamespace(stdout=listing if args[:2] == ['docker', 'ps'] else '')
            self.assertEqual(retention.auth(base, run), {'releases': 3, 'containers': 2})
            self.assertEqual(sorted(path.name for path in (base / 'releases').iterdir()),
                             sorted(['not-a-commit', *commits[:3], commits[5], commits[6]]))
            self.assertEqual([args for args in commands if args[:2] == ['docker', 'rm']],
                             [['docker', 'rm', f'passby-auth-{commits[4][:12]}-7280'], ['docker', 'rm', f'passby-auth-{commits[7][:12]}-7280']])
            self.assertFalse(any('image' in args for args in commands))


if __name__ == '__main__':
    unittest.main()
