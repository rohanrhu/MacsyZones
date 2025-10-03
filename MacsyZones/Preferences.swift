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

        return get(screenNumber: screenNumber, spaceNumber: spaceNumber)
    }

    static func getCurrentScreenAndSpace() -> (Int, Int)? {
        guard let focusedScreen = getFocusedScreen(),
              let screenIndex = NSScreen.screens.firstIndex(of: focusedScreen) else {
            return nil
        }

        guard let spaceNumber = getCurrentSpaceNumber() else {
            return nil
        }

        return (screenIndex, spaceNumber)
    }

    static func getCurrentSpaceNumber() -> Int? {
        let connection = CGSMainConnectionID()

        if let unmanagedDisplaySpaces = CGSCopyManagedDisplaySpaces(connection) {
            if let displaySpaces = unmanagedDisplaySpaces.takeRetainedValue() as? [[String: Any]],
               let currentSpaceDict = displaySpaces.first,
               let currentSpace = currentSpaceDict["Current Space"] as? NSDictionary,
               let activeSpaceID = currentSpace["ManagedSpaceID"] as? Int {
                   return activeSpaceID
               }
        }
        return nil
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
        }
    }
    
    func startObserving() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: nil,
            using: { _ in
                stopEditing()
                isFitting = false
                userLayouts.hideAllSectionWindows()
                if #available(macOS 12.0, *) { quickSnapper.close() }
                
                if !appSettings.selectPerDesktopLayout { return }
                
                self.switchToCurrent()
            }
        )
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil,
            using: { _ in
                if #available(macOS 12.0, *) { quickSnapper.close() }
                if !appSettings.selectPerDesktopLayout { return }
                
                if let layoutName = self.getCurrent() {
                    userLayouts.currentLayoutName = layoutName
                    
                    for (_, layout) in userLayouts.layouts {
                        layout.hideAllWindows()
                    }
                }
            }
        )
    }
}
