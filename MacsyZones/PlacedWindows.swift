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

import Foundation

class PlacedWindows {
    static var windows: [UInt32: Int] = [:]
    static var elements: [UInt32: AXUIElement] = [:]
    static var layouts: [UInt32: String] = [:]
    
    static func place(windowId: UInt32, layoutName: String, sectionNumber: Int, element: AXUIElement) {
        windows[windowId] = sectionNumber
        elements[windowId] = element
        layouts[windowId] = layoutName
    }
    
    static func unplace(windowId: UInt32) {
        windows.removeValue(forKey: windowId)
        elements.removeValue(forKey: windowId)
        layouts.removeValue(forKey: windowId)
    }
    
    static func isPlaced(windowId: UInt32) -> Bool {
        return windows.keys.contains(windowId)
    }
    
    static func isPlaced(layoutName: String, windowId: UInt32) -> Bool {
        return layouts.keys.contains(windowId) && layouts[windowId] == layoutName
    }
}
