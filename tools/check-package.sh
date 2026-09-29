#!/usr/bin/env bash
# Validates a built release zip: both production manifests and every runtime
# module they load must be present, and nothing development-only may ship.
# Usage: tools/check-package.sh <package.zip>
set -euo pipefail

zip_path="${1:?usage: tools/check-package.sh <package.zip>}"
addon="AsgardsGuildTithe"
production_manifests=("${addon}_Camelot.toc" "${addon}_Mainline.toc")
forbidden_patterns=(
    "^${addon}/${addon}Dev_"
    "^${addon}/tests/"
    "^${addon}/tools/"
    "^${addon}/docs/"
    "^${addon}/ai/"
    "^${addon}/\.github/"
    "^${addon}/\.pkgmeta$"
)

entries="$(unzip -Z1 "$zip_path")"
failures=0

fail() {
    echo "FAIL $1"
    failures=$((failures + 1))
}

has_entry() {
    printf '%s\n' "$entries" | grep -Fxq -- "$1"
}

manifest_versions=()
for manifest in "${production_manifests[@]}"; do
    path="${addon}/${manifest}"
    if ! has_entry "$path"; then
        fail "missing production manifest $path"
        continue
    fi

    contents="$(unzip -p "$zip_path" "$path" | tr -d '\r')"
    manifest_versions+=("$(printf '%s\n' "$contents" | sed -n 's/^## Version:[[:space:]]*//p')")

    while IFS= read -r module; do
        [ -z "$module" ] && continue
        has_entry "${addon}/${module//\\//}" || fail "$manifest loads ${module}, which is not in the package"
    done < <(printf '%s\n' "$contents" | grep -v '^##' | grep -E '\.(lua|xml)$' || true)
done

if [ "${#manifest_versions[@]}" -eq 2 ] && [ "${manifest_versions[0]}" != "${manifest_versions[1]}" ]; then
    fail "production manifests disagree on version: ${manifest_versions[0]} vs ${manifest_versions[1]}"
fi

for pattern in "${forbidden_patterns[@]}"; do
    matches="$(printf '%s\n' "$entries" | grep -E -- "$pattern" || true)"
    [ -n "$matches" ] && fail "development-only files packaged: $(printf '%s' "$matches" | tr '\n' ' ')"
done

# Only the supported production manifests may ship; any other manifest would
# claim a client this release was not verified on.
extra_manifests="$(printf '%s\n' "$entries" | grep -E "^${addon}/[^/]+\.toc$" |
    grep -vFx -e "${addon}/${production_manifests[0]}" -e "${addon}/${production_manifests[1]}" || true)"
[ -n "$extra_manifests" ] && fail "unsupported manifests packaged: $(printf '%s' "$extra_manifests" | tr '\n' ' ')"

outside="$(printf '%s\n' "$entries" | grep -v "^${addon}/" || true)"
[ -n "$outside" ] && fail "files outside the ${addon}/ folder: $(printf '%s' "$outside" | tr '\n' ' ')"

if [ "$failures" -gt 0 ]; then
    echo "$failures package check(s) failed for $zip_path"
    exit 1
fi
echo "Package $zip_path passed: both production manifests, all runtime modules, no development files."
