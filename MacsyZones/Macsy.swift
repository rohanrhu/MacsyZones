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

func resizeAndMoveWindow(element: AXUIElement, newPosition: CGPoint, newSize: CGSize, retries: Int = 0, retryParent: Bool = false) {
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
    
    for i in 0..<(retries == 0 ? 1 : retries) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (0.05 * Double(i))) { [element] in
            var sizeValue: CGSize
            
            var positionValue = newPosition
            if let positionAXValue = AXValueCreate(.cgPoint, &positionValue) {
                let result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionAXValue)
                
                if result != .success {
                    debugLog("Failed to set window position, error code: \(result.rawValue)")
                    debugLog(getWindowDetails(element: element))
                }
            }
            
            sizeValue = newSize
            if let sizeAXValue = AXValueCreate(.cgSize, &sizeValue) {
                let result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeAXValue)
                
                if result != .success {
                    debugLog("Failed to set window size, error code: \(result.rawValue)")
                    debugLog(getWindowDetails(element: element))
                }
            }
        }
        
        if let windowId = getWindowID(from: element),
           case let (currentSize, currentPosition) = getWindowSizeAndPosition(from: windowId)
        {
            if currentSize == newSize && currentPosition == newPosition {
                break
            }
        } else {
            break
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
    guard let position = getAXPosition(for: targetWindow) else { return }
    
    var newPosition: CGPoint = position
    var newSize: CGSize = targetWindow.frame.size
    
    if let targetScreen, let sectionConfig {
        let rect = sectionConfig.getAXRect(on: targetScreen)
        newPosition = rect.origin
        newSize = rect.size
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

