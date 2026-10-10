#!/usr/bin/env bash
# Sets the game interface version(s) in the repository's manifests for one
# client: its production and development manifests and the test expectation in
# tests/spec/bootstrap_spec.lua. Releases do not use these values; they take
# the FOREVER_INTERFACE and RETAIL_INTERFACE repository variables instead (see
# docs/packaging.md). Use this to keep the development install current.
#
# Usage: tools/set-interface.sh <forever|retail> <interface> [interface...]
#   tools/set-interface.sh retail 120200
#   tools/set-interface.sh forever 16001 16002
#
# Read a client's interface in game with: /dump (select(4, GetBuildInfo()))
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    echo "Usage: tools/set-interface.sh <forever|retail> <interface> [interface...]" >&2
    exit 1
}

[ "$#" -ge 2 ] || usage
client="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
shift

case "$client" in
    forever)
        suffix="_Camelot"
        test_name="Forever"
        variable_name="FOREVER_INTERFACE"
        ;;
    retail)
        suffix="_Mainline"
        test_name="Retail"
        variable_name="RETAIL_INTERFACE"
        ;;
    *)
        usage
        ;;
esac

for interface in "$@"; do
    if [[ ! "$interface" =~ ^[1-9][0-9]{4,5}$ ]]; then
        echo "Interface versions are 5 or 6 digit numbers, such as 16001 or 120100; got '$interface'." >&2
        exit 1
    fi
done

# "16001, 16002" in manifests and tests.
toc_value="$(printf '%s, ' "$@")"
toc_value="${toc_value%, }"
export toc_value test_name

for manifest in "AsgardsGuildTithe${suffix}.toc" "AsgardsGuildTitheDev${suffix}.toc"; do
    perl -pi -e 's/^## Interface:.*$/## Interface: $ENV{toc_value}/' "$repo_root/$manifest"
done

perl -pi -e 's/(\{ name = "\Q$ENV{test_name}\E", suffix = "[^"]*", interface = ")[^"]*(" \})/$1$ENV{toc_value}$2/' \
    "$repo_root/tests/spec/bootstrap_spec.lua"

# Every place must now agree; a missed file means the formats have drifted.
status=0
for manifest in "AsgardsGuildTithe${suffix}.toc" "AsgardsGuildTitheDev${suffix}.toc"; do
    grep -qxF "## Interface: $toc_value" "$repo_root/$manifest" || { echo "Not updated: $manifest" >&2; status=1; }
done
grep -qF "name = \"$test_name\", suffix = \"$suffix\", interface = \"$toc_value\"" \
    "$repo_root/tests/spec/bootstrap_spec.lua" || { echo "Not updated: tests/spec/bootstrap_spec.lua" >&2; status=1; }

if [ "$status" -ne 0 ]; then
    exit "$status"
fi
echo "Set the ${test_name} manifests to interface ${toc_value}. Releases use the ${variable_name} variable."
