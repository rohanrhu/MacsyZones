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

class UserLayouts: UserData, ObservableObject {
    @Published var layouts: [String: UserLayout] = [:]
    
    var defaultLayout: UserLayout {
        .init(name: "Default", sectionConfigs: [.defaultSection])
    }
    
    @Published var currentLayoutName: String = "Default"
    
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
                layouts["Default"] = defaultLayout
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
            currentLayoutName = "Default"
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
}

struct SectionConfig: Codable {
    var number: Int? = nil
    var widthPercentage: CGFloat
    var heightPercentage: CGFloat
    var xPercentage: CGFloat
    var yPercentage: CGFloat
    
    static var defaultSection: SectionConfig {
        .init(widthPercentage: 0.5, heightPercentage: 0.5, xPercentage: 0.25, yPercentage: 0.25)
    }
    
    func getRect(on targetScreen: NSScreen? = nil) -> NSRect {
        var screen: NSScreen
        
        if let targetScreen {
            screen = targetScreen
        } else {
            guard let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else {
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
            guard let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else {
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
