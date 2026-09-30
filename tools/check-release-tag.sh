#!/usr/bin/env bash
# Confirms a release tag is a valid version, and that the production
# manifests take their version from the tag (the packager replaces
# @project-version@ with the tag), so a hard-coded version can never ship.
# Usage: tools/check-release-tag.sh <tag>   (for example v0.2.0 or v0.2.0-beta1)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag="${1:-}"

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
    echo "Release tags look like v1.2.3 or v1.2.3-beta1; got '$tag'." >&2
    exit 1
fi

status=0
for manifest in AsgardsGuildTithe_Camelot.toc AsgardsGuildTithe_Mainline.toc; do
    declared="$(sed -n 's/^## Version:[[:space:]]*//p' "$repo_root/$manifest" | tr -d '\r[:space:]')"
    if [ "$declared" != "@project-version@" ]; then
        echo "$manifest declares version '$declared'; it must be @project-version@ so the release tag is used." >&2
        status=1
    fi
done

if [ "$status" -eq 0 ]; then
    echo "Tag $tag is valid; the package will be versioned $tag."
fi
exit "$status"
