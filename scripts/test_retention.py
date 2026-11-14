"""Isolated checks for server release retention; never touches a real server."""
import os, pathlib, sys, tempfile, unittest

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


if __name__ == '__main__':
    unittest.main()
