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
    var snapHighlightStrategy: SnapHighlightStrategy?
}

class AppSettings: UserData, ObservableObject {
    // Default values
    private static let defaultModifierKey: String = "Control"
    private static let defaultSnapKey: String = "Shift"
    private static let defaultModifierKeyDelay: Int = 1000
    private static let defaultFallbackToPreviousSize: Bool = true
    private static let defaultOnlyFallbackToPreviousSizeWithUserEvent: Bool = true
    private static let defaultSelectPerDesktopLayout: Bool = true
    private static let defaultPrioritizeCenterToSnap: Bool = true
    private static let defaultShakeToSnap: Bool = true
    private static let defaultShakeAccelerationThreshold: CGFloat = 50000.0
    private static let defaultSnapResize: Bool = true
    private static let defaultSnapResizeThreshold: CGFloat = 33.0
    private static let defaultQuickSnapShortcut: String = "Control+Shift+S"
    private static let defaultSnapWithRightClick: Bool = true
    private static let defaultShowSnapResizersOnHover: Bool = true
    private static let defaultCycleWindowsForwardShortcut: String = "Command+]"
    private static let defaultCycleWindowsBackwardShortcut: String = "Command+["
    private static let defaultSnapHighlightStrategy: SnapHighlightStrategy = .centerProximity
    
    @Published var modifierKey: String = defaultModifierKey
    @Published var snapKey: String = defaultSnapKey
    @Published var modifierKeyDelay: Int = defaultModifierKeyDelay
    @Published var fallbackToPreviousSize: Bool = defaultFallbackToPreviousSize
    @Published var onlyFallbackToPreviousSizeWithUserEvent: Bool = defaultOnlyFallbackToPreviousSizeWithUserEvent
    @Published var selectPerDesktopLayout: Bool = defaultSelectPerDesktopLayout
    @Published var prioritizeCenterToSnap: Bool = defaultPrioritizeCenterToSnap
    @Published var shakeToSnap: Bool = defaultShakeToSnap
    @Published var shakeAccelerationThreshold: CGFloat = defaultShakeAccelerationThreshold
    @Published var snapResize: Bool = defaultSnapResize
    @Published var snapResizeThreshold: CGFloat = defaultSnapResizeThreshold
    @Published var quickSnapShortcut: String = defaultQuickSnapShortcut
    @Published var snapWithRightClick: Bool = defaultSnapWithRightClick
    @Published var showSnapResizersOnHover: Bool = defaultShowSnapResizersOnHover
    @Published var cycleWindowsForwardShortcut: String = defaultCycleWindowsForwardShortcut
    @Published var cycleWindowsBackwardShortcut: String = defaultCycleWindowsBackwardShortcut
    @Published var snapHighlightStrategy: SnapHighlightStrategy = defaultSnapHighlightStrategy

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
    
    @MainActor
    func resetToDefaults() {
        modifierKey = Self.defaultModifierKey
        snapKey = Self.defaultSnapKey
        modifierKeyDelay = Self.defaultModifierKeyDelay
        fallbackToPreviousSize = Self.defaultFallbackToPreviousSize
        onlyFallbackToPreviousSizeWithUserEvent = Self.defaultOnlyFallbackToPreviousSizeWithUserEvent
        selectPerDesktopLayout = Self.defaultSelectPerDesktopLayout
        prioritizeCenterToSnap = Self.defaultPrioritizeCenterToSnap
        shakeToSnap = Self.defaultShakeToSnap
        shakeAccelerationThreshold = Self.defaultShakeAccelerationThreshold
        snapResize = Self.defaultSnapResize
        snapResizeThreshold = Self.defaultSnapResizeThreshold
        quickSnapShortcut = Self.defaultQuickSnapShortcut
        snapWithRightClick = Self.defaultSnapWithRightClick
        showSnapResizersOnHover = Self.defaultShowSnapResizersOnHover
        cycleWindowsForwardShortcut = Self.defaultCycleWindowsForwardShortcut
        cycleWindowsBackwardShortcut = Self.defaultCycleWindowsBackwardShortcut
        snapHighlightStrategy = Self.defaultSnapHighlightStrategy
        
        if #available(macOS 12.0, *) {
            quickSnapper.toggleHotkey?.register(for: quickSnapShortcut)
            cycleForwardHotkey.register(for: cycleWindowsForwardShortcut)
            cycleBackwardHotkey.register(for: cycleWindowsBackwardShortcut)
        }
        
        save()
    }
}

let appSettings = AppSettings()
