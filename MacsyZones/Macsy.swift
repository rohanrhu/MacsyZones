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

class ActualSelectedLayout: ObservableObject {
    @Published var selectedLayout: String = spaceLayoutPreferences.getCurrent() ?? userLayouts.currentLayoutName
}

let actualSelectedLayout = ActualSelectedLayout()

var isFitting = false
var isEditing = false

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
        print("Failed to retrieve window info")
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
        print("Failed to retrieve window bounds")
        return (nil, nil)
    }
}

func getWindowID(from axElement: AXUIElement) -> UInt32? {
    var windowID: UInt32 = 0
    let result = _AXUIElementGetWindow(axElement, &windowID)

    if result == .success {
        return windowID
    } else {
        print("Failed to get window ID, error code: \(result.rawValue)")
        return nil
    }
}

func onObserverNotification(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    var result: AXError
    
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
    
    var position: CGPoint = .zero
    var positionRef: CFTypeRef?
    result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
    if result == .success {
        AXValueGetValue(positionRef as! AXValue, AXValueType.cgPoint, &position)
    }
 
    switch notification as String {
    case kAXWindowMovedNotification:
        onWindowMoved(observer: observer, element: element, notification: notification, title: title as! String, position: position)
        break
    case kAXUIElementDestroyedNotification:
        print("App exited: \(title as! String)")
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

func onWindowMoved(observer: AXObserver, element: AXUIElement, notification: CFString, title: String, position: CGPoint) {
    if isEditing { return }
    
    let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
    
    let mouseLocation = NSEvent.mouseLocation
    var hoveredSectionWindow: SectionWindow?
    
    if isFitting {
        if appSettings.prioritizeCenterToSnap {
            for sectionWindow in userLayouts.currentLayout.layoutWindow.sectionWindows {
                let screenSize = focusedScreen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
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
                let screenSize = focusedScreen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
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
        
        toLeaveElement = element
        toLeaveSectionWindow = hoveredSectionWindow
    }
    
    guard let windowId = getWindowID(from: element) else {
        print("Failed to get window ID")
        return
    }
    
    if PlacedWindows.isPlaced(windowId: windowId) && !justDidMouseUp &&
        (!appSettings.onlyFallbackToPreviousSizeWithUserEvent || (NSEvent.pressedMouseButtons & 0x1) != 0)
    {
        PlacedWindows.unplace(windowId: windowId)
        
        if appSettings.fallbackToPreviousSize {
            guard let originalSize = OriginalWindowProperties.getWindowSize(for: windowId) else {
                print("Failed to get original window size")
                return
            }

            if case let (currentSize?, currentPosition?) = getWindowSizeAndPosition(from: windowId) {
                let mouseLocation = NSEvent.mouseLocation
                let relativeX = (mouseLocation.x - currentPosition.x) / currentSize.width

                let widthDifference = currentSize.width - originalSize.width
                if widthDifference != 0 {
                    let newXPosition = mouseLocation.x - (originalSize.width * relativeX)
                    
                    resizeAndMoveWindow(element: element,
                                        newPosition: CGPoint(x: newXPosition, y: currentPosition.y),
                                        newSize: originalSize)
                }
            } else {
                resizeWindow(element: element, newSize: originalSize)
                print("Window resized to original size!")
            }
        }
    }
    
    justDidMouseUp = false
    
    if appSettings.shakeToSnap {
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
                            actualSelectedLayout.selectedLayout = layoutName
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
        print("Failed to get window title, error code: \(result.rawValue)")
        return nil
    }
    
    return title
}

func resizeAndMoveWindow(element: AXUIElement, newPosition: CGPoint, newSize: CGSize) {
    var positionValue = newPosition
    let positionAXValue = AXValueCreate(.cgPoint, &positionValue)
    
    if let positionAXValue = positionAXValue {
        let result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionAXValue)
        
        if result != .success {
            print("Failed to set window position, error code: \(result.rawValue)")
        }
    }
    
    var sizeValue = newSize
    let sizeAXValue = AXValueCreate(.cgSize, &sizeValue)
    
    if let sizeAXValue = sizeAXValue {
        let result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeAXValue)
        
        if result != .success {
            print("Failed to set window size, error code: \(result.rawValue)")
        }
    }
}

func resizeWindow(element: AXUIElement, newSize: CGSize) {
    var sizeValue = newSize
    let sizeAXValue = AXValueCreate(.cgSize, &sizeValue)
    
    if let sizeAXValue = sizeAXValue {
        let result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeAXValue)
        
        if result != .success {
            print("Failed to set window size, error code: \(result.rawValue)")
        }
    }
}

func onMouseUp(event: NSEvent) {
    if isEditing { return }
    
    let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
    
    guard let screenSize = focusedScreen?.frame else { return }
    guard let window = toLeaveElement else { return }
    guard let windowId = getWindowID(from: window) else { return }
    
    if let sectionWindow = toLeaveSectionWindow {
        if isFitting {
            OriginalWindowProperties.updateWindowSize(windowID: windowId)
            
            let topLeftPosition = CGPoint(x: sectionWindow.window.frame.origin.x, y: screenSize.height - sectionWindow.window.frame.origin.y - sectionWindow.window.frame.height)
            resizeAndMoveWindow(element: window, newPosition: topLeftPosition, newSize: sectionWindow.window.frame.size)
            toLeaveElement = nil
            toLeaveSectionWindow = nil
            
            PlacedWindows.place(windowId: windowId, sectionIndex: 0)
            
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
