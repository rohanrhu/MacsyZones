#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$repo_root/MacsyZones/QuickSnapper.swift"

swiftc -parse "$source_file"

# Execute production methods verbatim against deterministic UI collaborators.
# No AppKit import, NSApplication, real dispatch/animation, or app bundle is used.
# The extractor counts braces so nested animation/delay closures stay intact.
{
  cat "$repo_root/scripts/quicksnapper_lifecycle_stubs.swift"
  awk '
    BEGIN {
      count = split("open close setWindows snapToZone advanceLifecycleGeneration isCurrentLifecycle clampSelectedIndex selectWindow selectedWindowForHotkey", names, " ")
      for (i = 1; i <= count; i++) wanted[names[i]] = 1
    }
    !capturing && /^[[:space:]]*(private[[:space:]]+)?func[[:space:]]/ {
      name = $0
      sub(/^.*func[[:space:]]+/, "", name)
      sub(/\(.*/, "", name)
      if (name in wanted) {
        capturing = 1
        depth = 0
        found++
      }
    }
    capturing {
      print
      braces = $0
      depth += gsub(/\{/, "{", braces)
      braces = $0
      depth -= gsub(/\}/, "}", braces)
      if (depth == 0) capturing = 0
    }
    END {
      if (capturing || found != count) {
        print "Failed to extract all QuickSnapper production methods" > "/dev/stderr"
        exit 1
      }
    }
  ' "$source_file"
  # Execute the actual queued Left/Right task bodies as delivered hotkeys. Only
  # their async wrapper is replaced by a callable method; statements are intact.
  awk '
    /prevLayoutHotkey = GlobalHotkey/ { nextMethod = "deliverPreviousLayout" }
    /nextLayoutHotkey = GlobalHotkey/ { nextMethod = "deliverNextLayout" }
    nextMethod != "" && /Task \{ @MainActor in/ {
      print "func " nextMethod "() {"
      nextMethod = ""
      capturing = 1
      depth = 1
      found++
      next
    }
    capturing {
      print
      braces = $0
      depth += gsub(/\{/, "{", braces)
      braces = $0
      depth -= gsub(/\}/, "}", braces)
      if (depth == 0) capturing = 0
    }
    END { if (capturing || found != 2) exit 1 }
  ' "$source_file"
  cat "$repo_root/scripts/quicksnapper_lifecycle_assertions.swift"
} | swift -

# Supplement execution with scoped wiring checks for Task delivery paths not
# represented by the synchronous holder: registration and Enter/Escape delivery.
awk '
  /func registerHotkeys\(\)/ { section = "register" }
  /func unregisterHotkeys\(\)/ { section = "unregister" }
  /doneHotkey = GlobalHotkey/ { section = "done" }
  /closeHotkey = GlobalHotkey/ { section = "close" }
  section == "register" && /let lifecycleGeneration = self.lifecycleGeneration/ { foundRegisterCapture = 1 }
  section == "unregister" && /let lifecycleGeneration = self.lifecycleGeneration/ { foundUnregisterCapture = 1 }
  section == "register" && /guard self.isCurrentLifecycle\(lifecycleGeneration\), self.isOpen else/ { foundRegister = 1 }
  section == "unregister" && /guard self.isCurrentLifecycle\(lifecycleGeneration\), !self.isOpen else/ { foundUnregister = 1 }
  section == "done" && /guard self.isOpen else/ { foundDone = 1 }
  section == "close" && /guard self.isOpen else/ { foundClose = 1 }
  END {
    if (!(foundRegisterCapture && foundUnregisterCapture && foundRegister && foundUnregister && foundDone && foundClose)) {
      print "Missing guarded asynchronous registration or Enter/Escape wiring" > "/dev/stderr"
      exit 1
    }
  }
' "$source_file"
echo 'PASS: queued registration and Enter/Escape guard wiring'
