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

class UserData {
    var name: String
    var data: String
    var fileName: String
    var filePath: URL

    init(name: String, data: String, fileName: String) {
        self.name = name
        self.data = data
        self.fileName = fileName
        
        let fileManager = FileManager.default
        let appName = Bundle.main.bundleIdentifier ?? "MacsyZones"
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupportDirectory.appendingPathComponent(appName)
        
        self.filePath = appDirectory.appendingPathComponent(fileName)
        
        if !fileManager.fileExists(atPath: appDirectory.path) {
            do {
                try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                debugLog("Error creating config directory: \(error)")
            }
        }
        
        load()
    }
    
    func save() {
        let fileManager = FileManager.default
        let appName = Bundle.main.bundleIdentifier ?? "MacsyZones"
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupportDirectory.appendingPathComponent(appName)

        if !fileManager.fileExists(atPath: appDirectory.path) {
            do {
                try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                debugLog("Error creating directory: \(error)")
                return
            }
        }

        let filePath = appDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: filePath, atomically: true, encoding: .utf8)
        } catch (let error) {
            debugLog("Error saving user data: \(error)")
        }
    }
    
    func load() {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: filePath.path) {
            debugLog("File doesn't exist, creating it with default data")
            save()
        } else {
            do {
                data = try String(contentsOf: filePath, encoding: .utf8)
            } catch (let error) {
                debugLog("Error loading user data: \(error)")
            }
        }
    }
}

class UserLayout {
    var name: String
    var sectionConfigs: [Int:SectionConfig] {
        didSet {
            layoutWindow.sectionConfigs = sectionConfigs
            
            for sectionWindow in layoutWindow.sectionWindows {
                sectionWindow.sectionConfig = sectionConfigs[sectionWindow.sectionConfig.number!]!
            }
        }
    }
    
    let layoutWindow: LayoutWindow
    
    init(name: String, sectionConfigs: [SectionConfig]) {
        self.name = name
        self.sectionConfigs = [:]
        
        var numberI = 1
        
        for var sectionConfig in sectionConfigs {
            let prevNumber = sectionConfig.number ?? 0
            
            if prevNumber == 0 {
                sectionConfig.number = numberI
                self.sectionConfigs[numberI] = sectionConfig
            } else if prevNumber >= numberI {
                self.sectionConfigs[prevNumber] = sectionConfig
                numberI = prevNumber
            } else {
                self.sectionConfigs[prevNumber] = sectionConfig
            }
            
            numberI += 1
        }
        
        self.layoutWindow = LayoutWindow(name: name, sectionConfigs: Array(self.sectionConfigs.values))
    }
    
    func reArrange() {
        let sectionConfigs = self.sectionConfigs.values.sorted { $0.number! < $1.number! }
        
        var newSectionConfigs: [Int:SectionConfig] = [:]
        
        var numberI = 1
        
        for sectionConfig in sectionConfigs {
            let sectionWindow = layoutWindow.sectionWindows.first(where: { $0.number == sectionConfig.number })!
            
            var newSectionConfig = sectionConfig
            newSectionConfig.number = numberI
            
            sectionWindow.reset(sectionConfig: newSectionConfig)
            
            newSectionConfigs[numberI] = newSectionConfig
            
            numberI += 1
        }
        
        self.sectionConfigs = newSectionConfigs
    }
    
    func hideAllWindows() {
        for sectionWindow in layoutWindow.sectionWindows {
            sectionWindow.window.orderOut(nil)
            sectionWindow.editorWindow.orderOut(nil)
        }
        
        layoutWindow.window.orderOut(nil)
        
        for sectionResizer in layoutWindow.sectionResizers {
            sectionResizer.orderOut(nil)
        }
    }
    
    func show(showLayouts: Bool = true, showSnapresizers: Bool = false) {
        layoutWindow.show(showLayouts: showLayouts, showSnapResizers: showSnapresizers)
    }
}

struct UpdateStateData: Codable {
    var attemptedVersion: String?
    var targetVersion: String?
}

class UpdateState: UserData, ObservableObject {
    @Published var attemptedVersion: String?
    @Published var targetVersion: String?
    
    init() {
        super.init(name: "UpdateState", data: "{}", fileName: "UpdateState.json")
    }
    
    override func load() {
        super.load()
        
        let jsonData = data.data(using: .utf8)!
        
        do {
            let state = try JSONDecoder().decode(UpdateStateData.self, from: jsonData)
            self.attemptedVersion = state.attemptedVersion
            self.targetVersion = state.targetVersion
        } catch {
            debugLog("Error parsing update state JSON: \(error)")
        }
    }
    
    override func save() {
        do {
            let state = UpdateStateData(
                attemptedVersion: attemptedVersion,
                targetVersion: targetVersion
            )
            
            let jsonData = try JSONEncoder().encode(state)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                data = jsonString
                super.save()
            }
        } catch {
            debugLog("Error encoding update state JSON: \(error)")
        }
    }
    
    func setUpdateAttempt(currentVersion: String, targetVersion: String) {
        self.attemptedVersion = currentVersion
        self.targetVersion = targetVersion
        save()
    }
    
    func clearUpdateAttempt() {
        self.attemptedVersion = nil
        self.targetVersion = nil
        save()
    }
    
    func hasFailedUpdate(currentVersion: String) -> Bool {
        guard let attemptedVersion = attemptedVersion,
              let targetVersion = targetVersion else {
            return false
        }
        
        return attemptedVersion == currentVersion && targetVersion != currentVersion
    }
}

class UserLayouts: UserData, ObservableObject {
    @Published var layouts: [String: UserLayout] = [:]
    
    var defaultLayout: UserLayout {
        .init(name: "Some Zones", sectionConfigs: [
            .init(number: 1, widthPercentage: 0.45, heightPercentage: 0.45, xPercentage: 0.2, yPercentage: 0.2, name: "Main Zone"),
            .init(number: 2, widthPercentage: 0.35, heightPercentage: 0.35, xPercentage: 0.55, yPercentage: 0.55, name: "Secondary Zone"),
            .init(number: 4, widthPercentage: 0.6, heightPercentage: 0.12, xPercentage: 0.2, yPercentage: 0.01, name: "Status Bar"),
            .init(number: 5, widthPercentage: 0.15, heightPercentage: 0.15, xPercentage: 0.84, yPercentage: 0.01, name: "Notification Corner"),
            .init(number: 6, widthPercentage: 0.8, heightPercentage: 0.2, xPercentage: 0.1, yPercentage: 0.79, name: "Media Controls"),
        ])
    }
    
    var fourCornersLayout: UserLayout {
        .init(name: "Four Corners Plus", sectionConfigs: [
            // Top-left corner
            .init(number: 1, widthPercentage: 0.45, heightPercentage: 0.45, xPercentage: 0.025, yPercentage: 0.025, name: "Top Left"),
            // Top-right corner
            .init(number: 2, widthPercentage: 0.45, heightPercentage: 0.45, xPercentage: 0.525, yPercentage: 0.025, name: "Top Right"),
            // Bottom-left corner
            .init(number: 3, widthPercentage: 0.45, heightPercentage: 0.45, xPercentage: 0.025, yPercentage: 0.525, name: "Bottom Left"),
            // Bottom-right corner
            .init(number: 4, widthPercentage: 0.45, heightPercentage: 0.45, xPercentage: 0.525, yPercentage: 0.525, name: "Bottom Right"),
            // Center section
            .init(number: 5, widthPercentage: 0.3, heightPercentage: 0.3, xPercentage: 0.35, yPercentage: 0.35, name: "Center")
        ])
    }
    
    var threeColumnLayout: UserLayout {
        .init(name: "Three Columns", sectionConfigs: [
            .init(number: 1, widthPercentage: 0.3, heightPercentage: 0.9, xPercentage: 0.025, yPercentage: 0.05, name: "Left Column"),
            .init(number: 2, widthPercentage: 0.3, heightPercentage: 0.9, xPercentage: 0.35, yPercentage: 0.05, name: "Middle Column"),
            .init(number: 3, widthPercentage: 0.3, heightPercentage: 0.9, xPercentage: 0.675, yPercentage: 0.05, name: "Right Column")
        ])
    }
    
    @Published var currentLayoutName: String = "Some Zones"
    
    var currentLayout: UserLayout {
        layouts[currentLayoutName] ?? defaultLayout
    }
    
    override init(name: String = "UserLayouts", data: String = "[]", fileName: String = "UserLayouts.json") {
        super.init(name: name, data: data, fileName: fileName)
    }
    
    override func load() {
        super.load()
        
        let jsonData = data.data(using: .utf8)!
        
        do {
            let layoutConfigs = try JSONDecoder().decode([String:[SectionConfig]].self, from: jsonData)
            
            for (layoutName, sectionConfigs) in layoutConfigs {
                layouts[layoutName] = .init(name: layoutName, sectionConfigs: sectionConfigs)
            }
            
            if layouts.isEmpty {
                layouts["Some Zones"] = defaultLayout
                layouts["Four Corners Plus"] = fourCornersLayout
                layouts["Three Columns"] = threeColumnLayout
            } else {
                currentLayoutName = layouts.keys.first!
            }
            
            save()
        } catch {
            debugLog("Error parsing layouts JSON: \(error)")
        }
    }
    
    override func save() {
        do {
            let layoutConfigs = layouts.mapValues { userLayout in
                Array(userLayout.sectionConfigs.values)
            }
            let jsonData = try JSONEncoder().encode(layoutConfigs)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                data = jsonString
                super.save()
            }
        } catch {
            debugLog("Error encoding layouts JSON: \(error)")
        }
    }
    
    func setCurrentLayout(name: String) {
        if layouts.keys.contains(name) {
            currentLayoutName = name
        } else {
            currentLayoutName = "Some Zones"
        }
    }
    
    func selectLayout(_ layoutName: String) {
        currentLayoutName = layoutName
    }
    
    func hideAllSectionWindows() {
        for layout in layouts.values {
            for sectionWindow in layout.layoutWindow.sectionWindows {
                sectionWindow.window.orderOut(nil)
            }
        }
    }
    
    func createLayout(name: String) {
        stopEditing()
        currentLayout.hideAllWindows()
        
        if layouts.keys.contains(name) { return }
        
        let newLayout = UserLayout(name: name, sectionConfigs: [SectionConfig.defaultSection])
        layouts[name] = newLayout
        
        currentLayoutName = name
        spaceLayoutPreferences.setCurrent(layoutName: name)
        
        userLayouts.save()
    }
    
    func renameCurrentLayout(to newName: String) {
        stopEditing()
        
        if newName == currentLayoutName { return }
        
        if let layout = layouts[currentLayoutName] {
            layout.hideAllWindows()
            
            layout.name = newName
            layout.layoutWindow.name = newName
            
            layouts[newName] = layout
            
            let oldName = currentLayoutName
            layouts.removeValue(forKey: oldName)
            
            currentLayoutName = newName
            spaceLayoutPreferences.setCurrent(layoutName: newName)
            
            save()
        }
    }
    
    func removeCurrentLayout() {
        stopEditing()
        
        if layouts.count < 2 { return }
        
        if let layout = layouts[currentLayoutName] {
            layout.layoutWindow.closeAllWindows()
            
            layouts.removeValue(forKey: currentLayoutName)
            
            let fallbackLayout = layouts.keys.first!
            
            currentLayoutName = fallbackLayout
            spaceLayoutPreferences.setCurrent(layoutName: fallbackLayout)
        }
        
        save()
    }
    
    func duplicateCurrentLayout(newName: String) {
        stopEditing()
        currentLayout.hideAllWindows()
        
        if layouts.keys.contains(newName) { return }
        
        if let currentLayout = layouts[currentLayoutName] {
            let sectionConfigs = Array(currentLayout.sectionConfigs.values)
            let duplicatedLayout = UserLayout(name: newName, sectionConfigs: sectionConfigs)
            layouts[newName] = duplicatedLayout
            
            currentLayoutName = newName
            spaceLayoutPreferences.setCurrent(layoutName: newName)
            
            save()
        }
    }
}

struct SectionConfig: Codable {
    var number: Int? = nil
    var widthPercentage: CGFloat
    var heightPercentage: CGFloat
    var xPercentage: CGFloat
    var yPercentage: CGFloat
    var name: String?
    
    static var defaultSection: SectionConfig {
        .init(widthPercentage: 0.5, heightPercentage: 0.5, xPercentage: 0.25, yPercentage: 0.25, name: "Default Zone")
    }
    
    func getRect(on targetScreen: NSScreen? = nil) -> NSRect {
        var screen: NSScreen
        
        if let targetScreen {
            screen = targetScreen
        } else {
            guard let focusedScreen = getFocusedScreen() else {
                return NSRect(x: 0, y: 0, width: 800, height: 600)
            }
            
            screen = focusedScreen
        }

        let width = screen.frame.width * widthPercentage
        let height = screen.frame.height * heightPercentage

        let x = screen.frame.origin.x + (screen.frame.width * xPercentage)
        let y = screen.frame.origin.y + (screen.frame.height * yPercentage)

        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    func getAXRect(on targetScreen: NSScreen? = nil) -> NSRect {
        var screen: NSScreen
        
        if let targetScreen {
            screen = targetScreen
        } else {
            guard let focusedScreen = getFocusedScreen() else {
                return NSRect(x: 0, y: 0, width: 800, height: 600)
            }
            
            screen = focusedScreen
        }

        let width = screen.frame.width * widthPercentage
        let height = screen.frame.height * heightPercentage

        let x = screen.frame.origin.x + (screen.frame.width * xPercentage)
        
        let relY = (screen.frame.height - (screen.frame.height * yPercentage)) - height
        let y = screen.axY + relY

        return NSRect(x: x,
                      y: y,
                      width: width,
                      height: height)
    }
    
    func getUpdated(for targetWindow: NSWindow, on targetScreen: NSScreen) -> SectionConfig {
        var sectionConfig = self
        
        let width = targetWindow.frame.size.width
        let height = targetWindow.frame.size.height
        
        var x: CGFloat
        let y: CGFloat
        
        x = targetWindow.frame.origin.x - targetScreen.frame.origin.x
        y = targetWindow.frame.origin.y - targetScreen.frame.origin.y
        
        sectionConfig.heightPercentage = height / targetScreen.frame.size.height
        sectionConfig.widthPercentage = width / targetScreen.frame.size.width
        sectionConfig.xPercentage = x / targetScreen.frame.size.width
        sectionConfig.yPercentage = y / targetScreen.frame.size.height
        
        return sectionConfig
    }
    
    static func create(number: Int, for targetWindow: NSWindow, on targetScreen: NSScreen) -> SectionConfig {
        let width = targetWindow.frame.size.width
        let height = targetWindow.frame.size.height
        
        let x: CGFloat = targetWindow.frame.origin.x - targetScreen.frame.origin.x
        let y: CGFloat = targetWindow.frame.origin.y - targetScreen.frame.origin.y
        
        let heightPercentage = height / targetScreen.frame.size.height
        let widthPercentage = width / targetScreen.frame.size.width
        let xPercentage = x / targetScreen.frame.size.width
        let yPercentage = y / targetScreen.frame.size.height
        
        let sectionConfig = SectionConfig(number: number,
                                          widthPercentage: widthPercentage,
                                          heightPercentage: heightPercentage,
                                          xPercentage: xPercentage,
                                          yPercentage: yPercentage)
        
        return sectionConfig
    }
}

class SectionBounds {
    var widthPercentage: CGFloat = 0
    var heightPercentage: CGFloat = 0
    var xPercentage: CGFloat = 0
    var yPercentage: CGFloat = 0
    
    init(widthPercentage: CGFloat, heightPercentage: CGFloat, xPercentage: CGFloat, yPercentage: CGFloat) {
        self.widthPercentage = widthPercentage
        self.heightPercentage = heightPercentage
        self.xPercentage = xPercentage
        self.yPercentage = yPercentage
    }
    
    func toArray() -> [Float] { [
        Float(widthPercentage) * 100,
        Float(heightPercentage) * 100,
        Float(xPercentage) * 100,
        Float(yPercentage) * 100
    ] }
    
    func toDictionary() -> [String: Float] { [
        "widthPercentage": Float(widthPercentage) * 100,
        "heightPercentage": Float(heightPercentage) * 100,
        "xPercentage": Float(xPercentage) * 100,
        "yPercentage": Float(yPercentage) * 100
    ] }
    
    func toJSON() -> String? {
        let dictionary = toDictionary()
        if let jsonData = try? JSONSerialization.data(withJSONObject: dictionary, options: .prettyPrinted) {
            return String(data: jsonData, encoding: .utf8)
        }
        return nil
    }
}
