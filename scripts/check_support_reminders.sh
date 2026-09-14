#!/bin/bash
# Compile the production reminder lifecycle and settings JSON code with in-memory
# collaborators. This never imports AppKit, launches MacsyZones, or touches user
# settings. It does not validate SwiftUI callbacks, focus, or visual presentation.
# Requires the macOS Swift toolchain; run from any directory.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/macsyzones-support-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

{
    cat "$ROOT/scripts/tests/support-reminder-stubs.swift"

    # Keep the entire production schema and settings implementation, substituting
    # Combine for SwiftUI (only ObservableObject and Published are needed here).
    awk '
        /^import SwiftUI$/ { imports++; print "import Combine"; next }
        /^struct AppSettingsData: Codable \{/ { schemas++ }
        /^class AppSettings: UserData, ObservableObject \{/ { settings++ }
        { print }
        END {
            if (imports != 1 || schemas != 1 || settings != 1) {
                print "Settings.swift shape changed; review test extraction" > "/dev/stderr"
                exit 1
            }
        }
    ' "$ROOT/MacsyZones/Settings.swift"

    # Keep DonationReminder declarations and methods unchanged. Only replace its
    # AppKit/SwiftUI constructor with an in-memory panel constructor. The strict
    # boundaries/counts intentionally fail closed if this source shape changes.
    awk '
        /^let INTERVALS = / { intervals++; print }
        /^class DonationReminder \{/ { classes++; inside = 1 }
        inside {
            if (/^    init\(\) \{$/) {
                initializers++; inInit = 1
                print "    init() { panel = DonationReminderPanel() }"
                next
            }
            if (inInit) {
                if (/^    \}$/) inInit = 0
                next
            }
            if (/^    func count\(\) \{$/) counts++
            if (/^    func hide\(\) \{$/) hides++
            if (/^    func dismiss\(\) \{$/) dismisses++
            if (/^    func disableAutomaticReminders\(\) \{$/) disables++
            print
            if (/^\}$/) { endings++; inside = 0 }
        }
        END {
            if (intervals != 1 || classes != 1 || initializers != 1 ||
                counts != 1 || hides != 1 || dismisses != 1 || disables != 1 ||
                endings != 1 || inside || inInit) {
                print "DonationReminder.swift shape changed; review test extraction" > "/dev/stderr"
                exit 1
            }
        }
    ' "$ROOT/MacsyZones/DonationReminder.swift"

    cat "$ROOT/scripts/tests/support-reminder-assertions.swift"
} > "$TEST_DIR/main.swift"

xcrun swiftc -swift-version 5 "$TEST_DIR/main.swift" -o "$TEST_DIR/check-support-reminders"
"$TEST_DIR/check-support-reminders"
