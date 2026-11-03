#!/usr/bin/env bash
# Publish the website (site) or identity service (auth). The exact clean main
# commit is pushed to Gitee first; the server then fetches and builds it itself.
set -Eeuo pipefail
component="${1:-}"
[[ "$component" =~ ^(site|auth)$ ]] || { echo 'usage: scripts/publish.sh site|auth' >&2; exit 2; }
cd "$(dirname "$0")/.."
[[ "$(git symbolic-ref --short HEAD)" == main ]] || { echo 'Publish from main.' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit the complete release before publishing.' >&2; exit 1; }
release="$(git rev-parse HEAD)"
# Secret scan over the whole history and a dependency audit block a release.
gitleaks git --no-banner --redact --log-level warn .
npm audit --prefix server --omit=dev --audit-level=high
python3 scripts/test_retention.py
if [[ "$component" == site ]]; then
    node --test scripts/test-web.mjs
    for module in public/web/*.mjs; do node --check "$module"; done
else
    npm test --prefix server
fi
# origin pushes to Gitee and GitHub. Only Gitee carries the release; GitHub is a mirror.
git push origin main || echo 'A push reported an error; checking Gitee.' >&2
gitee="$(git ls-remote https://gitee.com/dozybot/PassBy.git refs/heads/main | cut -f1)"
[[ "$gitee" == "$release" ]] || { echo "Gitee main is ${gitee:-unreadable}, not $release." >&2; exit 1; }
git ls-remote https://github.com/dozybot001/PassBy.git refs/heads/main | grep -q "^$release" ||
    echo 'Warning: the GitHub mirror is not at this commit.' >&2
# Both the server and Gitee host keys come from the repository, never a scan.
gitee_keys="$(grep '^gitee\.com ' scripts/known_hosts | base64 | tr -d '\n')"
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o HostKeyAlias=wesaid-prod -o UserKnownHostsFile=scripts/known_hosts \
    wesaid-prod sudo -n bash -s -- "$component" "$release" "$gitee_keys" < scripts/release-from-gitee.sh
