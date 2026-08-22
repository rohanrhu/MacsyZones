#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_binary="${TMPDIR:-/tmp}/macsyzones-drag-session-tests"
module_cache="${TMPDIR:-/tmp}/macsyzones-swift-module-cache"

mkdir -p "$module_cache"

xcrun swiftc \
    -module-cache-path "$module_cache" \
    "$repo_root/MacsyZones/DragSessionState.swift" \
    "$repo_root/tests/DragSessionStateTests.swift" \
    -o "$test_binary"

"$test_binary"
