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
import Cocoa

struct ScreenSpacePair: Hashable, Codable {
    let screen: Int
    let space: Int
}

class SpaceLayoutPreferences: UserData {
    var spaces: [ScreenSpacePair: String] = [:]
    static let defaultConfigFileName = "SpaceLayoutPreferences.json"
    private var spaceTransitionGeneration = 0

    override init(name: String = "SpaceLayoutPreferences", data: String = "{}", fileName: String = SpaceLayoutPreferences.defaultConfigFileName) {
        super.init(name: name, data: data, fileName: fileName)
    }

    func set(screenNumber: Int, spaceNumber: Int, layoutName: String) {
        spaces[ScreenSpacePair(screen: screenNumber, space: spaceNumber)] = layoutName
        save()
    }

    func get(screenNumber: Int, spaceNumber: Int) -> String? {
        let name = spaces[ScreenSpacePair(screen: screenNumber, space: spaceNumber)]
        
        if name == nil {
            return nil
        }
        
        if !userLayouts.layouts.keys.contains(name!) {
            return userLayouts.layouts.values.first?.name
        }
        
        return name
    }

    func setCurrent(layoutName: String) {
        guard let (screenNumber, spaceNumber) = SpaceLayoutPreferences.getCurrentScreenAndSpace() else {
            debugLog("Unable to get the current screen and space")
            return
        }

        set(screenNumber: screenNumber, spaceNumber: spaceNumber, layoutName: layoutName)
    }

    func getCurrent() -> String? {
        guard let (screenNumber, spaceNumber) = SpaceLayoutPreferences.getCurrentScreenAndSpace() else {
            debugLog("Unable to get the current screen and space")
            return nil
        }

        debugLog("Getting layout for screen \(screenNumber) and space \(spaceNumber)")

        return get(screenNumber: screenNumber, spaceNumber: spaceNumber)
    }

    static func getCurrentScreenAndSpace() -> (Int, Int)? {
        guard let focusedScreen = getFocusedScreen() else { return nil }

        let screenIndex = getScreenNumber(screen: focusedScreen)

        guard let screenIndex else { return nil }
        guard let spaceNumber = getCurrentSpaceNumber(for: focusedScreen) else { return nil }

        debugLog("getCurrentScreenAndSpace(): screenIndex: \(screenIndex), spaceNumber: \(spaceNumber)")

        return (screenIndex, spaceNumber)
    }

    static func getCurrentSpaceNumber(for screen: NSScreen? = nil) -> Int? {
        let connection = CGSMainConnectionID()

        guard let managedSpaces = CGSCopyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }

        // Each display has its own "Current Space" when macOS' separate-Spaces
        // option is enabled. Match the NSScreen display UUID instead of using
        // CGSGetActiveSpace alone, which can describe a different monitor.
        let targetScreen = screen ?? getFocusedScreen()
        if let targetScreen,
           let displayIdentifier = displayIdentifier(for: targetScreen),
           let display = managedSpaces.first(where: {
               ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(displayIdentifier) == .orderedSame
           }),
           let spaceNumber = currentSpaceNumber(in: display) {
            return spaceNumber
        }

        // Preserve compatibility if macOS changes the private display
        // identifier format: fall back to the globally active Space.
        let activeSpaceID = UInt64(CGSGetActiveSpace(connection))
        for display in managedSpaces {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            if let index = spaces.firstIndex(where: {
                managedSpaceID(in: $0) == activeSpaceID
            }) {
                debugLog("Falling back to global active Space resolution")
                return index + 1
            }
        }

        return nil
    }

    private static func displayIdentifier(for screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func currentSpaceNumber(in display: [String: Any]) -> Int? {
        guard let currentSpace = display["Current Space"] as? [String: Any],
              let currentSpaceID = managedSpaceID(in: currentSpace),
              let spaces = display["Spaces"] as? [[String: Any]],
              let index = spaces.firstIndex(where: {
                  managedSpaceID(in: $0) == currentSpaceID
              })
        else { return nil }

        return index + 1
    }

    private static func managedSpaceID(in space: [String: Any]) -> UInt64? {
        if let number = space["ManagedSpaceID"] as? NSNumber {
            return number.uint64Value
        }
        return space["ManagedSpaceID"] as? UInt64
    }

    override func save() {
        do {
            let jsonData = try JSONEncoder().encode(spaces)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            data = jsonString
            super.save()
        } catch {
            debugLog("Error saving SpaceLayoutPreferences: \(error)")
        }
    }

    override func load() {
        super.load()
        do {
            if let jsonData = data.data(using: .utf8) {
                spaces = try JSONDecoder().decode([ScreenSpacePair: String].self, from: jsonData)
                debugLog("Preferences loaded successfully.")
            }
        } catch {
            debugLog("Error loading SpaceLayoutPreferences: \(error)")
        }
    }
    
    func switchToCurrent() {
        if let layoutName = self.getCurrent() {
            userLayouts.currentLayoutName = layoutName
            
            for (_, layout) in userLayouts.layouts {
                layout.hideAllWindows()
            }

            stopEditing()
            
            debugLog("Switched to layout: \(userLayouts.currentLayoutName) for current space")
        }
    }

    @MainActor
    private func reconcileSpaceTransition(generation: Int, attempt: Int = 0) {
        guard generation == spaceTransitionGeneration else { return }

        let layoutResolved: Bool
        if appSettings.selectPerDesktopLayout {
            if let layoutName = getCurrent() {
                userLayouts.setCurrentLayout(name: layoutName)
                layoutResolved = true
                debugLog("Space transition resolved: layout=\(layoutName), attempt=\(attempt)")
            } else {
                layoutResolved = false
                debugLog("Space transition layout unresolved, attempt=\(attempt)")
            }
        } else {
            layoutResolved = true
        }

        // The AX manager performs its own per-process retries. Starting one
        // reconciliation here discovers windows exposed by the newly active
        // Space without blocking this transition on the main thread.
        if attempt == 0 || layoutResolved {
            WindowObserverManager.shared.refreshAllRunningApplications()
        }

        guard !layoutResolved, attempt < 3 else { return }
        let delay = 0.15 * Double(attempt + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.reconcileSpaceTransition(generation: generation, attempt: attempt + 1)
        }
    }
    
    func startObserving() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: nil,
            using: { _ in
                DispatchQueue.main.async {
                    self.spaceTransitionGeneration += 1
                    let generation = self.spaceTransitionGeneration

                    stopEditing()
                    setIsFitting(false)
                    resetDragSession()
                    for layout in userLayouts.layouts.values {
                        layout.hideAllWindows()
                    }
                    if #available(macOS 12.0, *) { quickSnapper.close() }

                    // Space resolution is asynchronous on macOS. A generation
                    // token prevents a delayed attempt from applying the layout
                    // of a Space the user has already left.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.reconcileSpaceTransition(generation: generation)
                    }
                }
            }
        )
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil,
            using: { _ in
                DispatchQueue.main.async {
                    if #available(macOS 12.0, *) { quickSnapper.close() }
                    setIsFitting(false)
                    resetDragSession()

                    for layout in userLayouts.layouts.values {
                        layout.hideAllWindows()
                    }

                    if appSettings.selectPerDesktopLayout,
                       let layoutName = self.getCurrent() {
                        userLayouts.currentLayoutName = layoutName
                    }

                    WindowObserverManager.shared.refreshAllRunningApplications()
                }
            }
        )
    }
}
