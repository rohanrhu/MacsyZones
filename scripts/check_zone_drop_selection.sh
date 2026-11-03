#!/bin/bash
set -euo pipefail

# Run from any directory. The optional source root is for isolated regression
# fixtures; by default this tests the production files in this checkout.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -gt 1 || "${1:-}" == -* ]]; then
    echo "Usage: bash scripts/check_zone_drop_selection.sh [source-root]" >&2
    exit 2
fi
source_root="${1:-$root}"
test_source="$(mktemp "${TMPDIR:-/tmp}/macsyzones-zone-drop-selection.XXXXXX")"
trap 'rm -f "$test_source"' EXIT

cat "$root/scripts/tests/zone-drop-stubs.swift" > "$test_source"

# Extract the real implementation, not a hand-maintained copy. Require exactly
# one start and end marker in the expected order so source drift fails closed.
awk '
    /^struct ZoneDropCandidate \{/ {
        starts++
        if (ends || inside) invalid = 1
        inside = 1
    }
    /^func getHoveredSectionWindow\(\)/ {
        ends++
        if (!inside) invalid = 1
        inside = 0
    }
    inside { print }
    END {
        if (starts != 1 || ends != 1 || inside || invalid) {
            print "FAIL: could not extract exactly one zone drop selection block" > "/dev/stderr"
            exit 1
        }
    }
' "$source_root/MacsyZones/Macsy.swift" >> "$test_source"

cat "$root/scripts/tests/zone-drop-assertions.swift" >> "$test_source"
echo "Testing zone drop selection from $source_root"
/usr/bin/swift "$test_source"
