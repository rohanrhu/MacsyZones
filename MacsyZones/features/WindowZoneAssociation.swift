// Passive window→zone association run only on:
//  - App load (after layouts & space selection)
//  - Layout switch (Popover picker)
//  - QuickSnapper activation (so already-aligned windows gain cycling/navigation benefits)
//
// No continuous listening / movement-based detection by design (user cannot reliably pixel-align manually).
// Tolerance: 6px each edge.
// 
// Associating windows ensures the internal list of windows MacsyZones manages is accurate and complete,
// which is important for features like window cycling to work as expected.
// Implementation notes:
//  - Only standard windows (role/subrole) are considered.
//  - Only unplaced windows are considered.
//  - The window's mid-point is used to determine which screen it is on.
//  - The window's frame is compared against each zone's frame on that screen, with a tolerance of 6px per edge.
//

import Cocoa
import Foundation

// Tolerance, in pixels, for matching window edges to zone edges.
// A window is considered to match a zone if all four edges are within this tolerance.
private let autoAssociateEdgeTolerance: CGFloat = 6.0

/// Attempt to associate all top-level standard windows that geometrically match a zone
/// for the current layout & active screen/space.
@MainActor
func autoAssociateAllWindowsInCurrentLayout(reason: String = "") {
    guard hasAccessibilityPermission else { return }
    guard let _ = SpaceLayoutPreferences.getCurrentScreenAndSpace() else { return }
    let running = NSWorkspace.shared.runningApplications
    for app in running {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) != .success { continue }
        guard let windowList = windowsRef as? [AXUIElement] else { continue }
        for element in windowList {
            guard let windowId = getWindowID(from: element) else { continue }
            if !PlacedWindows.isPlaced(windowId: windowId) {
                associateWindowWithCurrentLayout(element: element, reason: reason)
            }
        }
    }
}

/// Associate a single AX window with current layout if geometry matches a zone.
/// Mirrors filtering used when initially observing windows in AppDelegate (standard window with non-empty title).
@discardableResult
@MainActor
func associateWindowWithCurrentLayout(element: AXUIElement, reason: String = "") -> Bool {
    guard hasAccessibilityPermission else { return false }
    guard let (screenNumber, workspaceNumber) = SpaceLayoutPreferences.getCurrentScreenAndSpace() else { return false }
    let sections = userLayouts.currentLayout.layoutWindow.sectionWindows
    guard !sections.isEmpty else { return false }

    // Quick skip if already placed (avoid logging + geometry work)
    guard let windowId = getWindowID(from: element) else { return false }
    if PlacedWindows.isPlaced(windowId: windowId) { return false }

    // Role / subrole filtering (same style as observer setup)
    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    if (roleRef as? String) != kAXWindowRole { return false }
    var subroleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
    if (subroleRef as? String) != kAXStandardWindowSubrole { return false }

    // Geometry
    let (sizeOpt, posOpt) = getWindowSizeAndPosition(from: windowId)
    guard let size = sizeOpt, let pos = posOpt else { return false }
    let windowFrame = CGRect(origin: pos, size: size)
    let midpoint = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) else { return false }

    let layoutName = userLayouts.currentLayoutName
    // debugLog("AA candidate windowId=\(windowId) frame=(x: \(Int(pos.x)), y: \(Int(pos.y)), w: \(Int(size.width)), h: \(Int(size.height))) layout=\(layoutName) zones=\(sections.count) reason=\(reason)")
    for sectionWindow in sections {
        let rect = sectionWindow.sectionConfig.getAXRect(on: screen)
        // debugLog("AA compare windowId=\(windowId) zone=\(sectionWindow.number) zoneFrame=(x: \(Int(rect.origin.x)), y: \(Int(rect.origin.y)), w: \(Int(rect.size.width)), h: \(Int(rect.size.height))) tol=\(Int(autoAssociateEdgeTolerance))")
        if rectMatchesWithinTolerance(window: windowFrame, zone: rect, tol: autoAssociateEdgeTolerance) {
            OriginalWindowProperties.update(windowID: windowId)
            PlacedWindows.place(windowId: windowId,
                                screenNumber: screenNumber,
                                workspaceNumber: workspaceNumber,
                                layoutName: layoutName,
                                sectionNumber: sectionWindow.number,
                                element: element)
            var titleRef: CFTypeRef?
            var windowTitle: String = "#" + String(windowId)
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success, let t = titleRef as? String, !t.isEmpty {
                windowTitle = t
            }
            debugLog("Associated window \(windowTitle) → zone #\(sectionWindow.number) (reason=\(reason))")
            return true
        }
    }
    return false
}


private func rectMatchesWithinTolerance(window: CGRect, zone: CGRect, tol: CGFloat) -> Bool {
    let originMatch = abs(window.origin.x - zone.origin.x) <= tol && abs(window.origin.y - zone.origin.y) <= tol
    let sizeMatch = abs(window.size.width - zone.size.width) <= tol && abs(window.size.height - zone.size.height) <= tol
    return originMatch && sizeMatch
}
