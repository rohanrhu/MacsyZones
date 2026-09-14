#!/bin/bash
set -euo pipefail

# Run from any directory. The optional source root is for isolated regression
# fixtures; by default this tests the production files in this checkout.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -gt 1 || "${1:-}" == -* ]]; then
    echo "Usage: bash scripts/check_lazy_lifecycle.sh [source-root]" >&2
    exit 2
fi
source_root="${1:-$root}"
test_source="$(mktemp -t macsyzones-lazy-lifecycle)"
trap 'rm -f "$test_source"' EXIT

cat "$root/scripts/tests/lazy-stubs.swift" > "$test_source"

# Extract the real implementation, not a hand-maintained copy. Require exactly
# one start and end marker in the expected order so source drift fails closed.
awk '
    /^class UserLayout \{/ {
        starts++
        if (ends || inside) invalid = 1
        inside = 1
    }
    /^struct UpdateStateData:/ {
        ends++
        if (!inside) invalid = 1
        inside = 0
    }
    inside { print }
    END {
        if (starts != 1 || ends != 1 || inside || invalid) {
            print "FAIL: could not extract exactly one complete UserLayout" > "/dev/stderr"
            exit 1
        }
    }
' "$source_root/MacsyZones/UserData.swift" >> "$test_source"

awk '
    /^func startEditing\(\) \{/ {
        starts++
        if (ends || inside) invalid = 1
        inside = 1
    }
    /^func getMenuBarHeight\(\)/ {
        ends++
        if (!inside) invalid = 1
        inside = 0
    }
    inside {
        if ($0 ~ /^func stopEditing\(\) \{/) stops++
        if ($0 ~ /^func toggleEditing\(\) -> Bool \{/) toggles++
        print
    }
    END {
        if (starts != 1 || ends != 1 || stops != 1 || toggles != 1 || inside || invalid) {
            print "FAIL: could not extract startEditing, stopEditing, and toggleEditing exactly once" > "/dev/stderr"
            exit 1
        }
    }
' "$source_root/MacsyZones/Macsy.swift" >> "$test_source"

cat "$root/scripts/tests/lazy-assertions.swift" >> "$test_source"
echo "Testing lazy layout lifecycle from $source_root"
/usr/bin/swift "$test_source"
