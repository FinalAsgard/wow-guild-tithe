#!/usr/bin/env bash
# Builds the multi-client release zip locally with the BigWigs packager, never
# uploading, then validates its contents.
# Usage: tools/build-package.sh [release-dir]   (default: .release)
# The packager needs bash 4.3+. macOS ships 3.2, so point PACKAGER_BASH at a
# newer bash (for example from `brew install bash`).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="${1:-$repo_root/.release}"
packager_bash="${PACKAGER_BASH:-bash}"
# Pinned to an exact packager commit (the v2 tag as of 2026-09-28) so an
# upstream change cannot alter what runs here. Update deliberately.
packager_commit="e50a250f8705041e40f2fa1ddcb280a686d65aa0"
packager_url="https://raw.githubusercontent.com/BigWigsMods/packager/${packager_commit}/release.sh"

if ! "$packager_bash" -c '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) ))'; then
    echo "The packager needs bash 4.3 or newer; '$packager_bash' is older. Set PACKAGER_BASH to a newer bash." >&2
    exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

curl -fsSL "$packager_url" -o "$work_dir/release.sh"
# -d: never upload anywhere. The result is only a local zip.
"$packager_bash" "$work_dir/release.sh" -d -t "$repo_root" -r "$release_dir" | tee "$work_dir/packager.log"

# The packager tags game versions from the manifest suffixes. A suffix it does
# not recognize silently drops that client from the release.
if ! grep -q '^Build type: multi-version' "$work_dir/packager.log"; then
    echo "The packager did not tag this build for both Forever and Retail. Check the manifest suffixes." >&2
    exit 1
fi

zip_path="$(ls -t "$release_dir"/AsgardsGuildTithe-*.zip | head -n 1)"
"$repo_root/tools/check-package.sh" "$zip_path"
echo "Inspect the package with: unzip -l \"$zip_path\""
