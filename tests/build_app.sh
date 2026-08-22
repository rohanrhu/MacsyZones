#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-Debug}"

case "$configuration" in
    Debug|Release) ;;
    *)
        echo "Usage: $0 [Debug|Release]" >&2
        exit 2
        ;;
esac

derived_data="${TMPDIR:-/tmp}/MacsyZones-Tests-${configuration}-DerivedData"

xcodebuild -quiet \
    -project "$repo_root/MacsyZones.xcodeproj" \
    -scheme MacsyZones \
    -configuration "$configuration" \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "MacsyZones $configuration build: PASS"
