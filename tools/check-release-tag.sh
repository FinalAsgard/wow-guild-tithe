#!/usr/bin/env bash
# Confirms a release tag matches the version both production manifests
# declare, so a mistyped tag can never publish a mislabelled build.
# Usage: tools/check-release-tag.sh <tag>   (for example v0.2.0 or v0.2.0-beta1)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag="${1:-}"

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
    echo "Release tags look like v1.2.3 or v1.2.3-beta1; got '$tag'." >&2
    exit 1
fi
version="${tag#v}"

status=0
for manifest in AsgardsGuildTithe_Camelot.toc AsgardsGuildTithe_Mainline.toc; do
    declared="$(sed -n 's/^## Version:[[:space:]]*//p' "$repo_root/$manifest" | tr -d '\r[:space:]')"
    if [ "$declared" != "$version" ]; then
        echo "$manifest declares version '$declared', but the tag is '$tag'." >&2
        status=1
    fi
done

if [ "$status" -eq 0 ]; then
    echo "Tag $tag matches both production manifests."
fi
exit "$status"
