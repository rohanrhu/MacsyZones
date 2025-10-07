//
// Zone navigation feature state and core logic
//
// It will allow moving windows to adjacent zones (up/down/left/right) via keyboard shortcuts
//

import Foundation
import SwiftUI

// MARK: - Zone Navigation Core

// Feature-scoped state: indicates when a zone navigation move is in progress.
// Used to suppress unrelated UI (e.g., donation reminders) during keyboard-driven moves.
var isZoneNavigating = false

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
    var bestDistance: CGFloat = .greatestFiniteMagnitude
    
    let currentCenter = CGPoint(x: currentRect.midX, y: currentRect.midY)
    
    for sectionWindow in sectionWindows {
        // Skip current zone
        if sectionWindow.number == currentSection { continue }
        
        let zoneRect = sectionWindow.sectionConfig.getRect()
        let zoneCenter = CGPoint(x: zoneRect.midX, y: zoneRect.midY)
        
        // Check direction suitability
        let isInDirection: Bool
        let distance: CGFloat
        
        switch direction {
        case .left:
            isInDirection = (zoneRect.maxX <= currentRect.minX + 50)
            if isInDirection {
                let horizontalDistance = max(0, currentRect.minX - zoneRect.maxX)
                let verticalDistance = abs(zoneCenter.y - currentCenter.y)
                distance = horizontalDistance + (verticalDistance * 0.5)
            } else { distance = .greatestFiniteMagnitude }
        case .right:
            isInDirection = (zoneRect.minX >= currentRect.maxX - 50)
            if isInDirection {
                let horizontalDistance = max(0, zoneRect.minX - currentRect.maxX)
                let verticalDistance = abs(zoneCenter.y - currentCenter.y)
                distance = horizontalDistance + (verticalDistance * 0.5)
            } else { distance = .greatestFiniteMagnitude }
        case .up:
            isInDirection = (zoneRect.maxY <= currentRect.minY + 50)
            if isInDirection {
                let verticalDistance = max(0, currentRect.minY - zoneRect.maxY)
                let horizontalDistance = abs(zoneCenter.x - currentCenter.x)
                distance = verticalDistance + (horizontalDistance * 0.5)
            } else { distance = .greatestFiniteMagnitude }
        case .down:
            isInDirection = (zoneRect.minY >= currentRect.maxY - 50)
            if isInDirection {
                let verticalDistance = max(0, zoneRect.minY - currentRect.maxY)
                let horizontalDistance = abs(zoneCenter.x - currentCenter.x)
                distance = verticalDistance + (horizontalDistance * 0.5)
            } else { distance = .greatestFiniteMagnitude }
        }
        
        if isInDirection && distance < bestDistance {
            bestDistance = distance
            bestZone = sectionWindow
        }
    }
    
    return bestZone?.number
}
