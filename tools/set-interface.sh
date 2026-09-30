#!/usr/bin/env bash
# Sets the game interface version(s) one client supports, everywhere they are
# declared: that client's production and development manifests, the test
# expectation in tests/spec/bootstrap_spec.lua, and the README client table.
#
# Usage: tools/set-interface.sh <forever|retail> <interface> [interface...]
#   tools/set-interface.sh retail 120200
#   tools/set-interface.sh forever 16001 16002
#
# Read a client's interface in game with: /dump (select(4, GetBuildInfo()))
# Claim a new interface only after that client passes the in-game checklist.
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
        readme_label="World of Warcraft: Forever"
        ;;
    retail)
        suffix="_Mainline"
        test_name="Retail"
        readme_label="World of Warcraft Retail (live)"
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

# "16001, 16002" in manifests and tests; "`16001`, `16002`" in the README.
toc_value="$(printf '%s, ' "$@")"
toc_value="${toc_value%, }"
readme_value="$(printf '`%s`, ' "$@")"
readme_value="${readme_value%, }"
export toc_value readme_value test_name readme_label

for manifest in "AsgardsGuildTithe${suffix}.toc" "AsgardsGuildTitheDev${suffix}.toc"; do
    perl -pi -e 's/^## Interface:.*$/## Interface: $ENV{toc_value}/' "$repo_root/$manifest"
done

perl -pi -e 's/(\{ name = "\Q$ENV{test_name}\E", suffix = "[^"]*", interface = ")[^"]*(" \})/$1$ENV{toc_value}$2/' \
    "$repo_root/tests/spec/bootstrap_spec.lua"

# Replace only the last column of this client's README table row.
perl -pi -e 's/^(\| \Q$ENV{readme_label}\E \|.*\| )[^|]*( \|)$/$1$ENV{readme_value}$2/' \
    "$repo_root/README.md"

# Every place must now agree; a missed file means the formats have drifted.
status=0
for manifest in "AsgardsGuildTithe${suffix}.toc" "AsgardsGuildTitheDev${suffix}.toc"; do
    grep -qxF "## Interface: $toc_value" "$repo_root/$manifest" || { echo "Not updated: $manifest" >&2; status=1; }
done
grep -qF "name = \"$test_name\", suffix = \"$suffix\", interface = \"$toc_value\"" \
    "$repo_root/tests/spec/bootstrap_spec.lua" || { echo "Not updated: tests/spec/bootstrap_spec.lua" >&2; status=1; }
grep -qF "| $readme_label |" "$repo_root/README.md" && grep -F "| $readme_label |" "$repo_root/README.md" | grep -qF "$readme_value |" \
    || { echo "Not updated: README.md" >&2; status=1; }

if [ "$status" -ne 0 ]; then
    exit "$status"
fi
echo "Set ${test_name} to interface ${toc_value}. Run the tests, then the in-game checklist on ${test_name} before releasing."
