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

private var lastFocusedScreen: NSScreen?

func getFocusedScreen() -> NSScreen? {
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
        lastFocusedScreen = screen
        return screen
    }
    return lastFocusedScreen
}

func getScreenNumber(screen: NSScreen) -> Int? {
    var screenIndex: Int?

    if #available(macOS 26.0, *) {
        if let displayId = screen.cgDirectDisplayID {
            screenIndex = Int(displayId)
        }
    } else {
        screenIndex = NSScreen.screens.firstIndex(of: screen)
    }

    return screenIndex
}

func resolveScreen(screenNumber: Int) -> NSScreen? {
    if let screen = NSScreen.screens.first(where: { getScreenNumber(screen: $0) == screenNumber }) {
        return screen
    }

    return nil
}

func centerWindowOnFocusedScreen(_ window: NSWindow) {
    guard let screen = getFocusedScreen() else {
        window.center()
        return
    }
    
    let screenFrame = screen.visibleFrame
    let windowFrame = window.frame
    
    let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
    let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2
    
    window.setFrameOrigin(NSPoint(x: x, y: y))
}
