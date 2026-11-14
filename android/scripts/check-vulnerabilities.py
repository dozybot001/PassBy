#!/usr/bin/env python3
"""Checks the libraries that go into the app against the OSV vulnerability database (osv.dev).

Reads app/gradle.lockfile, takes what the release app carries at run time, and asks OSV about each
name and version. Only library names and versions are sent. Run before every release
(product standard 15.1.2); exits with 1 if anything is reported.
"""
import json, pathlib, sys, urllib.request

lockfile = pathlib.Path(__file__).resolve().parent.parent / 'app' / 'gradle.lockfile'
packages = []
for line in lockfile.read_text().splitlines():
    if line.startswith('#') or '=' not in line:
        continue
    coordinate, configurations = line.split('=', 1)
    if 'releaseRuntimeClasspath' not in configurations.split(','):
        continue
    group, name, version = coordinate.split(':')
    packages.append((f'{group}:{name}', version))

body = json.dumps({'queries': [{'package': {'ecosystem': 'Maven', 'name': n}, 'version': v} for n, v in packages]}).encode()
request = urllib.request.Request('https://api.osv.dev/v1/querybatch', data=body, headers={'Content-Type': 'application/json'})
results = json.loads(urllib.request.urlopen(request, timeout=60).read())['results']

found = 0
for (name, version), result in zip(packages, results):
    for vulnerability in result.get('vulns', []):
        found += 1
        print(f'{name} {version}: {vulnerability["id"]}')
print(f'{len(packages)} libraries checked, {found} known vulnerabilities')
sys.exit(1 if found else 0)
