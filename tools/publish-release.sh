#!/usr/bin/env bash
# Builds the tagged release with the BigWigs packager and uploads it to
# CurseForge (and a GitHub release). Run by the Release workflow when a
# version tag is pushed; see docs/packaging.md.
# Needs: CF_API_KEY (CurseForge API token) and CURSEFORGE_PROJECT_ID.
# GITHUB_OAUTH, when set, also publishes a GitHub release.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/packager.env
source "$repo_root/tools/packager.env"

if [ -z "${CF_API_KEY:-}" ] || [ -z "${CURSEFORGE_PROJECT_ID:-}" ]; then
    echo "Publishing needs the CF_API_KEY secret and the CURSEFORGE_PROJECT_ID variable (see docs/packaging.md)." >&2
    exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
curl -fsSL "https://raw.githubusercontent.com/BigWigsMods/packager/${PACKAGER_COMMIT}/release.sh" \
    -o "$work_dir/release.sh"
bash "$work_dir/release.sh" -t "$repo_root" -r "$work_dir/release" -p "$CURSEFORGE_PROJECT_ID" \
    | tee "$work_dir/packager.log"

# The packager tags game versions from the manifest suffixes; a build tagged
# for only one client would hide the release from the other.
if ! grep -q '^Build type: multi-version' "$work_dir/packager.log"; then
    echo "The packager did not tag this release for both Forever and Retail." >&2
    exit 1
fi
