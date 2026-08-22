#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

require_source() {
    local pattern="$1"
    local file="$2"
    local description="$3"

    if ! rg -F -q "$pattern" "$repo_root/$file"; then
        echo "FAIL: $description" >&2
        exit 1
    fi
}

reject_source() {
    local pattern="$1"
    local file="$2"
    local description="$3"

    if rg -F -q "$pattern" "$repo_root/$file"; then
        echo "FAIL: $description" >&2
        exit 1
    fi
}

require_source \
    'window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]' \
    'MacsyZones/Layout.swift' \
    'zone/grid overlays must remain available in every Space'

require_source \
    'kAXMovedNotification as CFString' \
    'MacsyZones/App.swift' \
    'window observers must request the continuous AX moved notification'

require_source \
    'Detected window drag via mouse fallback' \
    'MacsyZones/Macsy.swift' \
    'mouse-drag fallback must not be removed'

require_source \
    'WindowObserverManager.shared.refreshAllRunningApplications()' \
    'MacsyZones/Preferences.swift' \
    'Space changes must reconcile AX windows'

require_source \
    'spaceTransitionGeneration' \
    'MacsyZones/Preferences.swift' \
    'stale Space-transition retries must not select the wrong layout'

require_source \
    'getCurrentSpaceNumber(for: focusedScreen)' \
    'MacsyZones/Preferences.swift' \
    'layout selection must resolve the Space of the focused display'

require_source \
    'layout.hideAllWindows()' \
    'MacsyZones/Preferences.swift' \
    'Space changes must hide complete overlays, not only child zones'

reject_source \
    'observedWindowIDs' \
    'MacsyZones/App.swift' \
    'the old optimistic observer registry must not return'

echo 'test_source_invariants: PASS'
