//
// MacsyZones, macOS system utility for managing windows on your Mac.
// 
// https://macsyzones.com
// 
// Copyright © 2024, Oğuzhan Eroğlu <meowingcate@gmail.com> (https://meowingcat.io)
// 
// This file is part of MacsyZones.
// Licensed under GNU General Public License v3.0
// See LICENSE file.
//

import Cocoa
import ApplicationServices
import SwiftUI
import Accessibility
import CoreGraphics

var userLayouts: UserLayouts = .init()
var toLeaveElement: AXUIElement?
var toLeaveSectionWindow: SectionWindow?

var isFitting = false
var isEditing = false
var isQuickSnapping = false
var isSnapResizing = false
var isZoneNavigating = false

var isMovingAWindow = false

let spaceLayoutPreferences = SpaceLayoutPreferences()

func startEditing() {
    isFitting = false
    isEditing = true
    userLayouts.currentLayout.layoutWindow.startEditing()
}

func stopEditing() {
    isFitting = false
    isEditing = false
    userLayouts.currentLayout.layoutWindow.stopEditing()
}

@discardableResult
func toggleEditing() -> Bool {
    isFitting = false
    isEditing = !isEditing
    if isEditing {
        userLayouts.currentLayout.layoutWindow.startEditing()
    } else {
        userLayouts.currentLayout.layoutWindow.stopEditing()
    }
    return isEditing
}

func getMenuBarHeight() -> CGFloat? {
    if let screen = NSScreen.main {
        let fullHeight = screen.frame.height
        let visibleHeight = screen.visibleFrame.height
        let menuBarHeight = fullHeight - visibleHeight
        return menuBarHeight
    }
    return nil
}

func getWindowSizeAndPosition(from windowID: UInt32) -> (CGSize?, CGPoint?) {
    let windowList = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as NSArray?
    
    guard let windowInfoList = windowList as? [[String: AnyObject]], let windowInfo = windowInfoList.first else {
        debugLog("Failed to retrieve window info")
        return (nil, nil)
    }
    
    if let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {
        let x = boundsDict["X"] ?? 0
        let y = boundsDict["Y"] ?? 0
        let width = boundsDict["Width"] ?? 0
        let height = boundsDict["Height"] ?? 0
        
        let size = CGSize(width: width, height: height)
        let position = CGPoint(x: x, y: y)
        return (size, position)
    } else {
        debugLog("Failed to retrieve window bounds")
        return (nil, nil)
    }
}

func getWindowID(from axElement: AXUIElement) -> UInt32? {
    var windowID: UInt32 = 0
    let result = _AXUIElementGetWindow(axElement, &windowID)

    if result == .success {
        return windowID
    } else {
        debugLog("Failed to get window ID, error code: \(result.rawValue)")
        return nil
    }
}

func onObserverNotification(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    if isEditing { return }
    if isSnapResizing { return }
    
    var result: AXError
    
    var roleRef: CFTypeRef?
    result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    let role = roleRef as? String ?? "Unknown"
    
    if role != kAXWindowRole {
        return
    }
    
    var app: CFTypeRef?
    result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &app)
    guard result == .success else {
        return
    }
    
    var title: CFTypeRef?
    result = AXUIElementCopyAttributeValue(app as! AXUIElement, kAXTitleAttribute as CFString, &title)
    if result != .success {
        title = "" as CFTypeRef
    }
 
    switch notification as String {
    case kAXWindowMovedNotification:
        var position: CGPoint = .zero
        var positionRef: CFTypeRef?
        result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        if result == .success {
            AXValueGetValue(positionRef as! AXValue, AXValueType.cgPoint, &position)
        }
        
        onWindowMoved(observer: observer, element: element, notification: notification, title: title as! String, position: position)
        
        break
    case kAXUIElementDestroyedNotification:
        debugLog("App exited: \(title as! String)")
        break
    default:
        break
    }
}

let shakeCoolDown: TimeInterval = 0.75

var previousPosition: CGPoint?
var previousVelocity: CGPoint?
var previousTime: TimeInterval?
var lastShakeTime: TimeInterval = 0

var justDidMouseUp = false

func getHoveredSectionWindow() -> SectionWindow? {
    var hoveredSectionWindow: SectionWindow?
    
    guard let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else {
        for sectionWindow in userLayouts.currentLayout.layoutWindow.sectionWindows {
            sectionWindow.isHovered = false
        }
        return nil 
    }
    
    let mouseLocation = NSEvent.mouseLocation
    
    if isFitting {
        if appSettings.prioritizeCenterToSnap {
            for sectionWindow in userLayouts.currentLayout.layoutWindow.sectionWindows {
                let screenSize = focusedScreen.frame
                let bounds = sectionWindow.getBounds()
                let width = bounds.widthPercentage * screenSize.width
                let height = bounds.heightPercentage * screenSize.height
                let x = (bounds.xPercentage * screenSize.width + width / 2) - 50
                let y = (bounds.yPercentage * screenSize.height + height / 2) - 50
                
                if mouseLocation.x > x && mouseLocation.x < x + 100 && mouseLocation.y > y && mouseLocation.y < y + 100 {
                    hoveredSectionWindow = sectionWindow
                    break
                }
            }
        }
        
        if hoveredSectionWindow == nil {
            for sectionWindow in userLayouts.currentLayout.layoutWindow.sectionWindows {
                let screenSize = focusedScreen.frame
                let bounds = sectionWindow.getBounds()
                let width = bounds.widthPercentage * screenSize.width
                let height = bounds.heightPercentage * screenSize.height
                let x = bounds.xPercentage * screenSize.width
                let y = bounds.yPercentage * screenSize.height
                
                if mouseLocation.x > x && mouseLocation.x < x + width && mouseLocation.y > y && mouseLocation.y < y + height {
                    hoveredSectionWindow = sectionWindow
                    break
                }
            }
        }
    }

    for sectionWindow in userLayouts.currentLayout.layoutWindow.sectionWindows {
        sectionWindow.isHovered = (sectionWindow === hoveredSectionWindow)
    }
    
    return hoveredSectionWindow
}

func onWindowMoved(observer: AXObserver, element: AXUIElement, notification: CFString, title: String, position: CGPoint) {
    if isEditing { return }
    if isSnapResizing { return }
    if isQuickSnapping { return }
    
    var subroleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
    
    let subrole = subroleRef as? String ?? "Unknown"
    
    if subrole != kAXStandardWindowSubrole {
        return
    }
    
    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    
    let role = roleRef as? String ?? "Unknown"
    
    if role != kAXWindowRole {
        return
    }
    
    if NSEvent.pressedMouseButtons & 1 != 0 {
        isMovingAWindow = true
    }
    
    if let hoveredSectionWindow = getHoveredSectionWindow() {
        toLeaveElement = element
        toLeaveSectionWindow = hoveredSectionWindow
    }
    
    guard let windowId = getWindowID(from: element) else {
        debugLog("Failed to get window ID")
        return
    }
    
    let isPlaced = PlacedWindows.isPlaced(windowId: windowId)
    let originalSize = OriginalWindowProperties.getWindowSize(for: windowId)
    
    if isPlaced && !justDidMouseUp &&
        (!appSettings.onlyFallbackToPreviousSizeWithUserEvent || (NSEvent.pressedMouseButtons & 0x1) != 0)
    {
        PlacedWindows.unplace(windowId: windowId)
        
        if appSettings.fallbackToPreviousSize {
            if let originalSize,
               case let (currentSize?, currentPosition?) = getWindowSizeAndPosition(from: windowId)
            {
                let mouseLocation = NSEvent.mouseLocation
                let relativeX = (mouseLocation.x - currentPosition.x) / currentSize.width

                let widthDifference = currentSize.width - originalSize.width
                if widthDifference != 0 {
                    let newXPosition = mouseLocation.x - (originalSize.width * relativeX)
                    
                    resizeAndMoveWindow(element: element,
                                        newPosition: CGPoint(x: newXPosition, y: currentPosition.y),
                                        newSize: originalSize)
                }
            } else if let originalSize {
                resizeWindow(element: element, newSize: originalSize)
                debugLog("Window resized to original size!")
            }
        }
    }
    
    justDidMouseUp = false
    
    if isPlaced {
        return
    }
    
    if appSettings.shakeToSnap {

        var isSnapKeyPressed = NSEvent.modifierFlags.contains(.shift)

        if appSettings.snapKey != "None" {
            var snapKey: NSEvent.ModifierFlags = .shift
            
            if appSettings.snapKey == "Control" {
                snapKey = .control
            } else if appSettings.snapKey == "Command" {
                snapKey = .command
            } else if appSettings.snapKey == "Option" {
                snapKey = .option
            }
            
            isSnapKeyPressed = NSEvent.modifierFlags.contains(snapKey)
        }

        guard !isSnapKeyPressed else { return }
        
        let dependingPosition = NSEvent.mouseLocation
        let currentTime = Date().timeIntervalSince1970

        if let previousPosition = previousPosition, let previousTime = previousTime {
            let deltaTime = currentTime - previousTime
            let deltaPosition = CGPoint(x: dependingPosition.x - previousPosition.x, y: dependingPosition.y - previousPosition.y)
            let currentVelocity = CGPoint(x: deltaPosition.x / CGFloat(deltaTime), y: deltaPosition.y / CGFloat(deltaTime))

            if let previousVelocity = previousVelocity {
                let oppositeDirectionOnX = (currentVelocity.x > 0 && previousVelocity.x < 0) || (currentVelocity.x < 0 && previousVelocity.x > 0)
                let oppositeDirectionOnY = (currentVelocity.y > 0 && previousVelocity.y < 0) || (currentVelocity.y < 0 && previousVelocity.y > 0)
                
                let deltaVelocity = CGPoint(x: currentVelocity.x - previousVelocity.x, y: currentVelocity.y - previousVelocity.y)
                let acceleration = CGPoint(x: deltaVelocity.x / CGFloat(deltaTime), y: deltaVelocity.y / CGFloat(deltaTime))
                let accelerationMagnitude = sqrt(pow(acceleration.x, 2) + pow(acceleration.y, 2))

                if (oppositeDirectionOnX || oppositeDirectionOnY) && accelerationMagnitude > appSettings.shakeAccelerationThreshold && currentTime - lastShakeTime > shakeCoolDown {
                    lastShakeTime = currentTime
                    
                    if appSettings.selectPerDesktopLayout {
                        if let layoutName = spaceLayoutPreferences.getCurrent() {
                            userLayouts.currentLayoutName = layoutName
                        }
                    }

                    isFitting = !isFitting
                    if isFitting {
                        userLayouts.currentLayout.layoutWindow.show()
                    } else {
                        userLayouts.currentLayout.layoutWindow.hide()
                    }
                }
            }

            previousVelocity = currentVelocity
        }

        previousPosition = dependingPosition
        previousTime = currentTime
    }
}

func getWindowTitle(from axElement: AXUIElement?) -> String? {
    guard let axElement = axElement else {
        return nil
    }
    
    var titleRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(axElement, kAXTitleAttribute as CFString, &titleRef)
    
    guard result == .success, let title = titleRef as? String else {
        debugLog("Failed to get window title, error code: \(result.rawValue)")
        return nil
    }
    
    return title
}

func getWindowDetails(element: AXUIElement) -> String {
    var details = "Window details: "
    
    var title: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
    if let windowTitle = title as? String {
        details += "Title: \(windowTitle)"
    } else {
        details += "Title: Unknown"
    }
    
    return details
}

func isElementResizable(element: AXUIElement) -> Bool {
    var resizable: DarwinBoolean = true
    AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &resizable)
    return resizable.boolValue
}

func resizeAndMoveWindow(element: AXUIElement, newPosition: CGPoint, newSize: CGSize, retries: Int = 10, retryParent: Bool = false) {
    if retryParent && !isElementResizable(element: element) {
        debugLog("Window is not resizable! Trying parent window...")
        
        while true {
            var result: AXError
            var parentElementRef: CFTypeRef?
            
            result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentElementRef)
            if result != .success { return }
            
            var subroleRef: CFTypeRef?
            result = AXUIElementCopyAttributeValue(parentElementRef as! AXUIElement, kAXSubroleAttribute as CFString, &subroleRef)
            if result != .success { return }
            let subrole = subroleRef as! String
            
            let parentElement = parentElementRef as! AXUIElement
            
            if subrole == kAXStandardWindowSubrole {
                return resizeAndMoveWindow(element: parentElement, newPosition: newPosition, newSize: newSize, retries: retries)
            }
        }
        
        return
    }
    
    // Approach to reduce flickering:
    // 1. Immediate attempt (atomic set position + size)
    // 2. If after a short delay the window drifted (position OR size changed noticeably), perform one corrective pass with light staggered retries
    // We consider a drift if either axis differs more than 2px or size differs more than 2px (tolerates rapid sequential moves without over-correcting)
    var initialWindowId: UInt32? = getWindowID(from: element)
    var originalObserved: (CGSize?, CGPoint?) = (nil, nil)
    if let id = initialWindowId {
        originalObserved = getWindowSizeAndPosition(from: id)
    }

    // Immediate attempt
    var positionValue = newPosition
    if let positionAXValue = AXValueCreate(.cgPoint, &positionValue) {
        let result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionAXValue)
        if result != .success { debugLog("First pass: failed setting position (code: \(result.rawValue))") }
    }
    var sizeValue = newSize
    if let sizeAXValue = AXValueCreate(.cgSize, &sizeValue) {
        let result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeAXValue)
        if result != .success { debugLog("First pass: failed setting size (code: \(result.rawValue))") }
    }

    guard retries > 1, let id = initialWindowId else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak element] in
        guard let element else { return }
        let (curSizeOpt, curPosOpt) = getWindowSizeAndPosition(from: id)
        guard let curSize = curSizeOpt, let curPos = curPosOpt else { return }
        let sizeDrift = abs(curSize.width - newSize.width) > 2 || abs(curSize.height - newSize.height) > 2
        let posDrift = abs(curPos.x - newPosition.x) > 2 || abs(curPos.y - newPosition.y) > 2
        if !(sizeDrift || posDrift) { return }
        // Corrective light retries (max 3) with tiny stagger to gently converge
        for i in 0..<min(3, retries) {
            DispatchQueue.main.asyncAfter(deadline: .now() + (0.02 * Double(i))) { [weak element] in
                guard let element else { return }
                var p = newPosition
                if let pax = AXValueCreate(.cgPoint, &p) {
                    AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pax)
                }
                var s = newSize
                if let sax = AXValueCreate(.cgSize, &s) {
                    AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sax)
                }
            }
        }
    }
    
    /*
     * Fix macOS bug!
     * --------------
     * macOS has a bug, when you move & resize a window downward, the window is not being resized correctly.
     * This code fixes this buggy behavior of macOS 😇
     */
    if NSScreen.screens.count > 1 {
        var sizeValue = CGSize(width: newSize.width, height: newSize.height - 10)
        if let sizeAXValue = AXValueCreate(.cgSize, &sizeValue) {
            let result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeAXValue)
            
            if result != .success {
                debugLog("Failed to set window size, error code: \(result.rawValue)")
                debugLog(getWindowDetails(element: element))
            }
        }
    }
}

func getElementSizeAndPosition(element: AXUIElement) -> (size: CGSize, position: CGPoint)? {
    var result: AXError
    
    var sizeRef: CFTypeRef?
    result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &sizeRef)
    if result != .success {
        debugLog("Failed to get window size, error code: \(result.rawValue)")
        return nil
    }
    let size = sizeRef as! CGSize
    
    var positionRef: CFTypeRef?
    result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
    if result != .success {
        debugLog("Failed to get window position, error code: \(result.rawValue)")
        return nil
    }
    let position = positionRef as! CGPoint
    
    return (size, position)
}

func getAXPosition(for window: NSWindow) -> CGPoint? {
    let windowId = CGWindowID(window.windowNumber)
    
    let windowList = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowId) as NSArray?
    
    guard let windowInfoList = windowList as? [[String: AnyObject]], let windowInfo = windowInfoList.first else {
        debugLog("Failed to retrieve window info")
        return nil
    }
    
    if let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {
        guard let x = boundsDict["X"], let y = boundsDict["Y"] else {
            debugLog("Failed to retrieve window bounds from bounds dict")
            return nil
        }
        
        let position = CGPoint(x: x, y: y)
        
        return position
    } else {
        debugLog("Failed to retrieve window bounds")
    }
    
    return nil
}

extension NSScreen {
    var axY: CGFloat {
        let toppestY = NSScreen.screens.first!.frame.origin.y + NSScreen.screens.first!.frame.height
        return toppestY - (frame.origin.y + frame.height)
    }
}

func moveWindowToMatch(element: AXUIElement, targetWindow: NSWindow, targetScreen: NSScreen? = nil, sectionConfig: SectionConfig? = nil) {
    var newPosition: CGPoint
    var newSize: CGSize
    
    if let targetScreen, let sectionConfig {
        let rect = sectionConfig.getAXRect(on: targetScreen)
        newPosition = rect.origin
        newSize = rect.size
    } else {
        // Fallback to using target window position only when no section config is provided
        guard let position = getAXPosition(for: targetWindow) else { return }
        newPosition = position
        newSize = targetWindow.frame.size
    }
    
    resizeAndMoveWindow(element: element,
                        newPosition: newPosition,
                        newSize: newSize,
                        retries: 10)
}

func resizeWindow(element: AXUIElement, newSize: CGSize) {
    var sizeValue = newSize
    let sizeAXValue = AXValueCreate(.cgSize, &sizeValue)
    
    if let sizeAXValue = sizeAXValue {
        let result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeAXValue)
        
        if result != .success {
            debugLog("Failed to set window size, error code: \(result.rawValue)")
        }
    }
}

func getFocusedWindowAXUIElement() -> AXUIElement? {
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }
    
    let pid = frontmostApp.processIdentifier
    let focusedApp = AXUIElementCreateApplication(pid)
    
    var focusedWindow: AnyObject?
    let windowResult = AXUIElementCopyAttributeValue(focusedApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)
    
    guard windowResult == .success else {
        debugLog("Failed to get focused window!")
        return nil
    }
    
    return focusedWindow as! AXUIElement?
}

func onMouseUp(event: NSEvent) {
    isMovingAWindow = false
    
    if isQuickSnapping { return }
    
    if !isFitting { return }
    
    if isEditing || isSnapResizing || isQuickSnapping {
        isFitting = false
    }
    
    if let hoveredSectionWindow = getHoveredSectionWindow() {
        toLeaveElement = toLeaveElement ?? getFocusedWindowAXUIElement()
        toLeaveSectionWindow = hoveredSectionWindow
    }
    
    guard let window = toLeaveElement else {
        isFitting = false
        userLayouts.currentLayout.layoutWindow.hide()
        return
    }
    guard let windowId = getWindowID(from: window) else {
        isFitting = false
        userLayouts.currentLayout.layoutWindow.hide()
        toLeaveElement = nil
        return
    }
    
    if let sectionWindow = toLeaveSectionWindow {
        if isFitting {
            OriginalWindowProperties.update(windowID: windowId)
            
            moveWindowToMatch(element: window, targetWindow: sectionWindow.window)
            
            if let (screenNumber, workspaceNumber) = SpaceLayoutPreferences.getCurrentScreenAndSpace() {
                PlacedWindows.place(windowId: windowId,
                                    screenNumber: screenNumber,
                                    workspaceNumber: workspaceNumber,
                                    layoutName: userLayouts.currentLayoutName,
                                    sectionNumber: toLeaveSectionWindow!.number,
                                    element: toLeaveElement!)
            }
            
            toLeaveElement = nil
            toLeaveSectionWindow = nil
            
            isFitting = false
            userLayouts.currentLayout.layoutWindow.hide()
            
            justDidMouseUp = true
        }
    } else {
        isFitting = false
        userLayouts.currentLayout.layoutWindow.hide()
    }
    
    previousPosition = nil
    previousVelocity = nil
    previousTime = nil
    lastShakeTime = Date().timeIntervalSince1970 + 0.75
}

func onMouseMove(event: NSEvent) {
    if isEditing { return }
    if isSnapResizing { return }
    
    
}

// MARK: - Window Cycling Functions

func cycleWindowsInZone(forward: Bool) {
    guard let focusedElement = getFocusedWindowAXUIElement(),
          let focusedWindowId = getWindowID(from: focusedElement) else {
        debugLog("No focused window found for cycling")
        return
    }
    
    // Check if the focused window is placed in a zone
    guard PlacedWindows.isPlaced(windowId: focusedWindowId) else {
        debugLog("Focused window is not placed in any zone")
        return
    }
    
    let windowsInZone = getWindowsInSameZone(as: focusedWindowId)
    
    // Need at least 2 windows to cycle
    guard windowsInZone.count > 1 else {
        debugLog("Not enough windows in zone to cycle (found \(windowsInZone.count))")
        return
    }
    
    // Find current window index
    guard let currentIndex = windowsInZone.firstIndex(where: { $0.windowId == focusedWindowId }) else {
        debugLog("Could not find current window in zone list")
        return
    }
    
    // Calculate next index
    let nextIndex: Int
    if forward {
        nextIndex = (currentIndex + 1) % windowsInZone.count
    } else {
        nextIndex = (currentIndex - 1 + windowsInZone.count) % windowsInZone.count
    }
    
    let targetWindow = windowsInZone[nextIndex]
    
    // Activate the target window
    activateElementsWindow(element: targetWindow.element)
    
    debugLog("Cycled \(forward ? "forward" : "backward") to window \(targetWindow.windowId)")
}

// MARK: - Zone Navigation Functions
func snapWindowToZone(sectionNumber: Int, element: AXUIElement, windowId: UInt32) {
    let section = userLayouts.currentLayout.layoutWindow.sectionWindows.first(where: { $0.sectionConfig.number! == sectionNumber })
    if let section, let sectionWindow = section.window {
        guard let (screenNumber, workspaceNumber) = SpaceLayoutPreferences.getCurrentScreenAndSpace() else { return }
        guard let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else { return }
        
        if !PlacedWindows.isPlaced(windowId: windowId) { OriginalWindowProperties.update(windowID: windowId) }
        
        // Use immediate positioning for zone navigation to prevent flickering
    moveWindowToMatch(element: element, 
               targetWindow: sectionWindow, 
               targetScreen: focusedScreen, 
               sectionConfig: section.sectionConfig)
        
        PlacedWindows.place(windowId: windowId,
                            screenNumber: screenNumber,
                            workspaceNumber: workspaceNumber,
                            layoutName: userLayouts.currentLayoutName,
                            sectionNumber: sectionNumber,
                            element: element)
    }
}

enum ZoneDirection {
    case left, right, up, down
}

func moveWindowToAdjacentZone(direction: ZoneDirection) {
    debugLog("moveWindowToAdjacentZone called with direction: \(direction)")
    
    // Set zone navigation flag to suppress donation reminders
    isZoneNavigating = true
    debugLog("moveWindowToAdjacentZone - Set isZoneNavigating=true")
    
    // Use defer to ensure flag is reset when function exits
    defer {
        isZoneNavigating = false
        debugLog("moveWindowToAdjacentZone - Reset isZoneNavigating=false (defer)")
    }
    
    guard let focusedElement = getFocusedWindowAXUIElement(),
          let focusedWindowId = getWindowID(from: focusedElement) else {
        debugLog("moveWindowToAdjacentZone - No focused window found for zone navigation")
        return
    }
    
    debugLog("moveWindowToAdjacentZone - Found focused window ID: \(focusedWindowId)")
    
    // Get current zone if window is already placed
    let currentSectionNumber = PlacedWindows.isPlaced(windowId: focusedWindowId) ? 
        PlacedWindows.windows[focusedWindowId] : nil
    
    // Find target zone based on direction
    guard let targetSectionNumber = findAdjacentZone(
        from: currentSectionNumber,
        direction: direction,
        windowElement: focusedElement
    ) else {
        debugLog("moveWindowToAdjacentZone - No adjacent zone found in \(direction) direction")
        return
    }
    
    debugLog("moveWindowToAdjacentZone - Moving window \(focusedWindowId) from zone \(currentSectionNumber?.description ?? "none") to zone \(targetSectionNumber)")
    snapWindowToZone(sectionNumber: targetSectionNumber, element: focusedElement, windowId: focusedWindowId)
}

func findAdjacentZone(from currentSection: Int?, direction: ZoneDirection, windowElement: AXUIElement) -> Int? {
    let sectionWindows = userLayouts.currentLayout.layoutWindow.sectionWindows
    guard !sectionWindows.isEmpty else { return nil }
    
    // Get current window rect for reference
    let currentRect: NSRect
    if let currentSection = currentSection,
       let currentSectionWindow = sectionWindows.first(where: { $0.number == currentSection }) {
        currentRect = currentSectionWindow.sectionConfig.getRect()
    } else {
        // Use actual window position if not in a zone
        var position = CGPoint.zero
        var size = CGSize.zero
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionRef) == .success,
           let positionValue = positionRef {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        }
        
        if AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeValue = sizeRef {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        
        currentRect = NSRect(origin: position, size: size)
    }
    
    // Use edge-based logic for all other cases (including windows already in zones)
    var bestZone: SectionWindow?
    var bestDistance: CGFloat = CGFloat.greatestFiniteMagnitude
    
    let currentCenter = CGPoint(x: currentRect.midX, y: currentRect.midY)
    
    for sectionWindow in sectionWindows {
        // Skip current zone
        if sectionWindow.number == currentSection { continue }
        
        let zoneRect = sectionWindow.sectionConfig.getRect()
        let zoneCenter = CGPoint(x: zoneRect.midX, y: zoneRect.midY)
        
        // Check if zone is in the correct direction
        let isInDirection: Bool
        let distance: CGFloat
        
        switch direction {
        case .left:
            // Zone must be to the left: zone's right edge should be to the left of window's left edge
            isInDirection = (zoneRect.maxX <= currentRect.minX + 50) // Allow 50px overlap for better UX
            if isInDirection {
                // Distance from window's left edge to zone's right edge + vertical alignment penalty
                let horizontalDistance = max(0, currentRect.minX - zoneRect.maxX)
                let verticalDistance = abs(zoneCenter.y - currentCenter.y)
                distance = horizontalDistance + (verticalDistance * 0.5) // Weight vertical alignment less
            } else {
                distance = CGFloat.greatestFiniteMagnitude
            }
            
        case .right:
            // Zone must be to the right: zone's left edge should be to the right of window's right edge
            isInDirection = (zoneRect.minX >= currentRect.maxX - 50) // Allow 50px overlap for better UX
            if isInDirection {
                // Distance from window's right edge to zone's left edge + vertical alignment penalty
                let horizontalDistance = max(0, zoneRect.minX - currentRect.maxX)
                let verticalDistance = abs(zoneCenter.y - currentCenter.y)
                distance = horizontalDistance + (verticalDistance * 0.5) // Weight vertical alignment less
            } else {
                distance = CGFloat.greatestFiniteMagnitude
            }
            
        case .up:
            // Zone must be above: zone's bottom edge should be above window's top edge
            isInDirection = (zoneRect.maxY <= currentRect.minY + 50) // Allow 50px overlap for better UX
            if isInDirection {
                // Distance from window's top edge to zone's bottom edge + horizontal alignment penalty
                let verticalDistance = max(0, currentRect.minY - zoneRect.maxY)
                let horizontalDistance = abs(zoneCenter.x - currentCenter.x)
                distance = verticalDistance + (horizontalDistance * 0.5) // Weight horizontal alignment less
            } else {
                distance = CGFloat.greatestFiniteMagnitude
            }
            
        case .down:
            // Zone must be below: zone's top edge should be below window's bottom edge
            isInDirection = (zoneRect.minY >= currentRect.maxY - 50) // Allow 50px overlap for better UX
            if isInDirection {
                // Distance from window's bottom edge to zone's top edge + horizontal alignment penalty
                let verticalDistance = max(0, zoneRect.minY - currentRect.maxY)
                let horizontalDistance = abs(zoneCenter.x - currentCenter.x)
                distance = verticalDistance + (horizontalDistance * 0.5) // Weight horizontal alignment less
            } else {
                distance = CGFloat.greatestFiniteMagnitude
            }
        }
        
        if isInDirection && distance < bestDistance {
            bestDistance = distance
            bestZone = sectionWindow
        }
    }
    
    return bestZone?.number
}

func getWindowsInSameZone(as windowId: UInt32) -> [(windowId: UInt32, element: AXUIElement)] {
    guard let sectionNumber = PlacedWindows.windows[windowId],
          let layoutName = PlacedWindows.layouts[windowId],
          let screenNumber = PlacedWindows.screens[windowId],
          let workspaceNumber = PlacedWindows.workspaces[windowId] else {
        return []
    }
    
    var windowsInZone: [(windowId: UInt32, element: AXUIElement)] = []
    
    for (otherWindowId, otherSectionNumber) in PlacedWindows.windows {
        // Check if window is in the same zone (section, layout, screen, workspace)
        if otherSectionNumber == sectionNumber,
           PlacedWindows.layouts[otherWindowId] == layoutName,
           PlacedWindows.screens[otherWindowId] == screenNumber,
           PlacedWindows.workspaces[otherWindowId] == workspaceNumber,
           let element = PlacedWindows.elements[otherWindowId] {
            
            windowsInZone.append((windowId: otherWindowId, element: element))
        }
    }
    
    // Sort by window ID for consistent ordering
    windowsInZone.sort { $0.windowId < $1.windowId }
    
    return windowsInZone
}

func activateElementsWindow(element: AXUIElement) {
    // Get the application from the window element
    var pid: pid_t = 0
    let result = AXUIElementGetPid(element, &pid)
    
    guard result == .success else {
        debugLog("Failed to get PID for element")
        return
    }
    
    guard let app = NSRunningApplication(processIdentifier: pid) else {
        debugLog("Failed to get running application for PID \(pid)")
        return
    }
    
    // Activate the application and bring the window to front
    app.activate()
    
    // Use AX API to raise the specific window
    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    // Attempt to fetch a window id for logging (optional)
    if let id = getWindowID(from: element) {
        debugLog("Activated window \(id) in application \(app.localizedName ?? "Unknown")")
    } else {
        debugLog("Activated element in application \(app.localizedName ?? "Unknown")")
    }
}

func presentingShortcut(_ shortcut: String) -> String {
    let formattedShortcut = shortcut
        .replacingOccurrences(of: "Command", with: "⌘")
        .replacingOccurrences(of: "Control", with: "⌃")
        .replacingOccurrences(of: "Option", with: "⌥")
        .replacingOccurrences(of: "Shift", with: "⇧")
    
    return formattedShortcut
}
