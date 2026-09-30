#!/usr/bin/env bash
# Builds the tagged release with the BigWigs packager and uploads it to
# CurseForge. Run by the Release workflow when a GitHub release is published;
# see docs/packaging.md.
# Needs: CF_API_KEY (CurseForge API token) and CURSEFORGE_PROJECT_ID.
# PUBLISH_DIR, when set, receives a copy of the uploaded zip.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/packager.env
source "$repo_root/tools/packager.env"

if [ -z "${CF_API_KEY:-}" ] || [ -z "${CURSEFORGE_PROJECT_ID:-}" ]; then
    echo "Publishing needs the CF_API_KEY secret and the CURSEFORGE_PROJECT_ID variable (see docs/packaging.md)." >&2
    exit 1
fi
# The packager silently skips CurseForge for a non-numeric ID and treats 0 as
# "no project", which would publish only the GitHub release.
if [[ ! "$CURSEFORGE_PROJECT_ID" =~ ^[1-9][0-9]*$ ]]; then
    echo "CURSEFORGE_PROJECT_ID must be the numeric CurseForge project ID; got '$CURSEFORGE_PROJECT_ID'." >&2
    exit 1
fi

# The packager would rewrite the GitHub release's title and notes with its
# own changelog, so it never gets a GitHub token; the workflow attaches the
# zip to the release itself.
unset GITHUB_OAUTH

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

"$repo_root/tools/check-package.sh" "$work_dir"/release/AsgardsGuildTithe-*.zip

if [ -n "${PUBLISH_DIR:-}" ]; then
    mkdir -p "$PUBLISH_DIR"
    cp "$work_dir"/release/AsgardsGuildTithe-*.zip "$PUBLISH_DIR"/
fi
