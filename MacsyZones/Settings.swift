//
//  Settings.swift
//  MacsyZones
//
//  Created by Oğuzhan on 1.10.2025.
//

import SwiftUI

enum SnapHighlightStrategy: String, Codable {
    case centerProximity
    case flat
}

struct AppSettingsData: Codable {
    var modifierKey: String?
    var snapKey: String?
    var modifierKeyDelay: Int?
    var fallbackToPreviousSize: Bool?
    var onlyFallbackToPreviousSizeWithUserEvent: Bool?
    var selectPerDesktopLayout: Bool?
    var prioritizeCenterToSnap: Bool?
    var shakeToSnap: Bool?
    var shakeAccelerationThreshold: CGFloat?
    var snapResize: Bool?
    var snapResizeThreshold: CGFloat?
    var quickSnapShortcut: String?
    var snapWithRightClick: Bool?
    var showSnapResizersOnHover: Bool?
    var cycleWindowsForwardShortcut: String?
    var cycleWindowsBackwardShortcut: String?
    // Zone navigation shortcuts
    var moveZoneLeftShortcut: String?
    var moveZoneRightShortcut: String?
    var moveZoneUpShortcut: String?
    var moveZoneDownShortcut: String?
    var snapHighlightStrategy: SnapHighlightStrategy?
}

class AppSettings: UserData, ObservableObject {
    @Published var modifierKey: String = "Control"
    @Published var snapKey: String = "Shift"
    @Published var modifierKeyDelay: Int = 1000
    @Published var fallbackToPreviousSize: Bool = true
    @Published var onlyFallbackToPreviousSizeWithUserEvent: Bool = true
    @Published var selectPerDesktopLayout: Bool = true
    @Published var prioritizeCenterToSnap: Bool = true
    @Published var shakeToSnap: Bool = true
    @Published var shakeAccelerationThreshold: CGFloat = 50000.0
    @Published var snapResize: Bool = true
    @Published var snapResizeThreshold: CGFloat = 33.0
    @Published var quickSnapShortcut: String = "Control+Shift+S"
    @Published var snapWithRightClick: Bool = true
    @Published var showSnapResizersOnHover: Bool = true
    @Published var cycleWindowsForwardShortcut: String = "Command+]"
    @Published var cycleWindowsBackwardShortcut: String = "Command+["
    // Zone navigation default shortcuts (can be customized by user)
    @Published var moveZoneLeftShortcut: String = "Control+Option+Left"
    @Published var moveZoneRightShortcut: String = "Control+Option+Right"
    @Published var moveZoneUpShortcut: String = "Control+Option+Up"
    @Published var moveZoneDownShortcut: String = "Control+Option+Down"
    @Published var snapHighlightStrategy: SnapHighlightStrategy = .centerProximity

    init() {
        super.init(name: "AppSettings", data: "{}", fileName: "AppSettings.json")
    }

    override func load() {
        super.load()

        let jsonData = data.data(using: .utf8)!
        
        do {
            let settings = try JSONDecoder().decode(AppSettingsData.self, from: jsonData)
            
            self.modifierKey = settings.modifierKey ?? modifierKey
            self.snapKey = settings.snapKey ?? snapKey
            self.modifierKeyDelay = settings.modifierKeyDelay ?? modifierKeyDelay
            self.fallbackToPreviousSize = settings.fallbackToPreviousSize ?? fallbackToPreviousSize
            self.onlyFallbackToPreviousSizeWithUserEvent = settings.onlyFallbackToPreviousSizeWithUserEvent ?? onlyFallbackToPreviousSizeWithUserEvent
            self.selectPerDesktopLayout = settings.selectPerDesktopLayout ?? selectPerDesktopLayout
            self.prioritizeCenterToSnap = settings.prioritizeCenterToSnap ?? prioritizeCenterToSnap
            self.shakeToSnap = settings.shakeToSnap ?? shakeToSnap
            self.shakeAccelerationThreshold = settings.shakeAccelerationThreshold ?? shakeAccelerationThreshold
            self.snapResize = settings.snapResize ?? snapResize
            self.snapResizeThreshold = settings.snapResizeThreshold ?? snapResizeThreshold
            self.quickSnapShortcut = settings.quickSnapShortcut ?? quickSnapShortcut
            self.snapWithRightClick = settings.snapWithRightClick ?? snapWithRightClick
            self.showSnapResizersOnHover = settings.showSnapResizersOnHover ?? showSnapResizersOnHover
            self.cycleWindowsForwardShortcut = settings.cycleWindowsForwardShortcut ?? cycleWindowsForwardShortcut
            self.cycleWindowsBackwardShortcut = settings.cycleWindowsBackwardShortcut ?? cycleWindowsBackwardShortcut
            self.moveZoneLeftShortcut = settings.moveZoneLeftShortcut ?? moveZoneLeftShortcut
            self.moveZoneRightShortcut = settings.moveZoneRightShortcut ?? moveZoneRightShortcut
            self.moveZoneUpShortcut = settings.moveZoneUpShortcut ?? moveZoneUpShortcut
            self.moveZoneDownShortcut = settings.moveZoneDownShortcut ?? moveZoneDownShortcut
            self.snapHighlightStrategy = settings.snapHighlightStrategy ?? snapHighlightStrategy
        } catch {
            debugLog("Error parsing settings JSON: \(error)")
        }
    }

    override func save() {
        do {
            let settings = AppSettingsData(
                modifierKey: modifierKey,
                snapKey: snapKey,
                modifierKeyDelay: modifierKeyDelay,
                fallbackToPreviousSize: fallbackToPreviousSize,
                onlyFallbackToPreviousSizeWithUserEvent: onlyFallbackToPreviousSizeWithUserEvent,
                selectPerDesktopLayout: selectPerDesktopLayout,
                prioritizeCenterToSnap: prioritizeCenterToSnap,
                shakeToSnap: shakeToSnap,
                shakeAccelerationThreshold: shakeAccelerationThreshold,
                snapResize: snapResize,
                snapResizeThreshold: snapResizeThreshold,
                quickSnapShortcut: quickSnapShortcut,
                snapWithRightClick: snapWithRightClick,
                showSnapResizersOnHover: showSnapResizersOnHover,
                cycleWindowsForwardShortcut: cycleWindowsForwardShortcut,
                cycleWindowsBackwardShortcut: cycleWindowsBackwardShortcut,
                moveZoneLeftShortcut: moveZoneLeftShortcut,
                moveZoneRightShortcut: moveZoneRightShortcut,
                moveZoneUpShortcut: moveZoneUpShortcut,
                moveZoneDownShortcut: moveZoneDownShortcut,
                snapHighlightStrategy: snapHighlightStrategy
            )
            
            let jsonData = try JSONEncoder().encode(settings)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                data = jsonString
                super.save()
            }
        } catch {
            debugLog("Error encoding settings JSON: \(error)")
        }
    }
}

let appSettings = AppSettings()
