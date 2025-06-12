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
import CoreGraphics

class OriginalWindowProperties {
    static var windowSizeMap: [UInt32: CGSize] = [:]
    static var windowPositionMap: [UInt32: CGPoint] = [:]
    
    static func update(windowID: UInt32) {
        let windowList = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as NSArray?
        
        guard let windowInfoList = windowList as? [[String: AnyObject]], let windowInfo = windowInfoList.first else {
            debugLog("Failed to retrieve window info")
            return
        }
        
        if let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {
            let width = boundsDict["Width"] ?? 0
            let height = boundsDict["Height"] ?? 0
            let size = CGSize(width: width, height: height)
            windowSizeMap[windowID] = size
            
            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            let position = CGPoint(x: x, y: y)
            windowPositionMap[windowID] = position
        } else {
            debugLog("Failed to retrieve window bounds")
        }
    }
    
    static func getWindowSize(for windowID: UInt32) -> CGSize? {
        return windowSizeMap[windowID]
    }
    
    static func getWindowPosition(for windowID: UInt32) -> CGPoint? {
        return windowPositionMap[windowID]
    }
}
