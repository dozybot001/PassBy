#!/usr/bin/env bash
# Publish the website. The exact clean main commit is pushed to Gitee first; the
# server then fetches and builds it itself.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
[[ "$(git symbolic-ref --short HEAD)" == main ]] || { echo 'Publish from main.' >&2; exit 1; }
# The Android app is developed in the same checkout by another session and is not
# part of the website, so its work in progress does not block.
[[ -z "$(git status --porcelain -- . ':!android' ':!docs/android.md')" ]] || { echo 'Commit the complete release before publishing.' >&2; exit 1; }
release="$(git rev-parse HEAD)"
# A secret scan over the whole history blocks a release.
gitleaks git --no-banner --redact --log-level warn .
python3 scripts/test_retention.py
node scripts/export-format.mjs --check
# origin pushes to Gitee and GitHub. Only Gitee carries the release; GitHub is a mirror.
git push origin main || echo 'A push reported an error; checking Gitee.' >&2
gitee="$(git ls-remote https://gitee.com/dozybot/PassBy.git refs/heads/main | cut -f1)"
[[ "$gitee" == "$release" ]] || { echo "Gitee main is ${gitee:-unreadable}, not $release." >&2; exit 1; }
git ls-remote https://github.com/dozybot001/PassBy.git refs/heads/main | grep -q "^$release" ||
    echo 'Warning: the GitHub mirror is not at this commit.' >&2
# Both the server and Gitee host keys come from the repository, never a scan.
gitee_keys="$(grep '^gitee\.com ' scripts/known_hosts | base64 | tr -d '\n')"
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o HostKeyAlias=wesaid-prod -o UserKnownHostsFile=scripts/known_hosts \
    wesaid-prod sudo -n bash -s -- "$release" "$gitee_keys" < scripts/release-from-gitee.sh
