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
                print("Error creating config directory: \(error)")
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
                print("Error creating directory: \(error)")
                return
            }
        }

        let filePath = appDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: filePath, atomically: true, encoding: .utf8)
        } catch (let error) {
            print("Error saving user data: \(error)")
        }
    }
    
    func load() {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: filePath.path) {
            print("File doesn't exist, creating it with default data")
            save()
        } else {
            do {
                data = try String(contentsOf: filePath, encoding: .utf8)
            } catch (let error) {
                print("Error loading user data: \(error)")
            }
        }
    }
}

class UserLayout {
    var name: String
    var sectionConfigs: [SectionConfig]
    let layoutWindow: LayoutWindow
    
    init(name: String, sectionConfigs: [SectionConfig]) {
        self.name = name
        self.sectionConfigs = sectionConfigs
        self.layoutWindow = LayoutWindow(name: name, sectionConfigs: sectionConfigs)
    }
}

class UserLayouts: UserData, ObservableObject {
    @Published var layouts: [String:UserLayout] = [:]
    
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
                save()
            } else {
                currentLayoutName = layouts.keys.first!
            }
        } catch {
            print("Error parsing layouts JSON: \(error)")
        }
    }
    
    override func save() {
        do {
            let layoutConfigs = layouts.mapValues { $0.sectionConfigs }
            let jsonData = try JSONEncoder().encode(layoutConfigs)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                data = jsonString
                super.save()
            }
        } catch {
            print("Error encoding layouts JSON: \(error)")
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
}

struct SectionConfig: Codable {
    var widthPercentage: CGFloat
    var heightPercentage: CGFloat
    var xPercentage: CGFloat
    var yPercentage: CGFloat
    
    static var defaultSection: SectionConfig {
        .init(widthPercentage: 0.5, heightPercentage: 0.5, xPercentage: 0.25, yPercentage: 0.25)
    }
}

class UserSettings: UserData {
    init() {
        super.init(name: "UserSettings", data: "{}", fileName: "UserSettings.json")
    }
    
    override func load() {
        super.load()
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
