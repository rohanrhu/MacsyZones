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

enum LayoutType: String, Codable {
    case zone
    case grid
}

struct GridConfig: Codable {
    var rows: Int
    var columns: Int

    static let defaultGrid = GridConfig(rows: 3, columns: 3)

    func cellAt(point: CGPoint, on screen: NSScreen) -> (row: Int, col: Int)? {
        let visible = screen.visibleFrame
        let relX = point.x - visible.origin.x
        let relY = point.y - visible.origin.y

        if relX < 0 || relY < 0 || relX > visible.width || relY > visible.height {
            return nil
        }

        let flippedY = visible.height - relY
        let col = Int(relX / (visible.width / CGFloat(columns)))
        let row = Int(flippedY / (visible.height / CGFloat(rows)))

        return (row: min(row, rows - 1), col: min(col, columns - 1))
    }

    func getSelectionRect(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int, on screen: NSScreen) -> NSRect {
        let minRow = min(fromRow, toRow)
        let maxRow = max(fromRow, toRow)
        let minCol = min(fromCol, toCol)
        let maxCol = max(fromCol, toCol)

        let visible = screen.visibleFrame
        let cellWidth = visible.width / CGFloat(columns)
        let cellHeight = visible.height / CGFloat(rows)

        let x = visible.origin.x + CGFloat(minCol) * cellWidth
        let width = CGFloat(maxCol - minCol + 1) * cellWidth
        let height = CGFloat(maxRow - minRow + 1) * cellHeight
        let y = visible.origin.y + visible.height - CGFloat(minRow) * cellHeight - height

        return NSRect(x: x, y: y, width: width, height: height)
    }

    func getSelectionAXRect(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int, on screen: NSScreen) -> NSRect {
        let minRow = min(fromRow, toRow)
        let maxRow = max(fromRow, toRow)
        let minCol = min(fromCol, toCol)
        let maxCol = max(fromCol, toCol)

        let visible = screen.visibleFrame
        let cellWidth = visible.width / CGFloat(columns)
        let cellHeight = visible.height / CGFloat(rows)

        let x = visible.origin.x + CGFloat(minCol) * cellWidth
        let width = CGFloat(maxCol - minCol + 1) * cellWidth
        let height = CGFloat(maxRow - minRow + 1) * cellHeight

        let toppestY = NSScreen.screens.first!.frame.origin.y + NSScreen.screens.first!.frame.height
        let visibleTopInAX = toppestY - (visible.origin.y + visible.height)
        let axY = visibleTopInAX + CGFloat(minRow) * cellHeight

        return NSRect(x: x, y: axY, width: width, height: height)
    }
}

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
            try data.write(to: filePath, atomically: false, encoding: .utf8)
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
    var layoutType: LayoutType

    var sectionConfigs: [Int:SectionConfig] {
        didSet {
            layoutWindow.sectionConfigs = sectionConfigs

            for sectionWindow in layoutWindow.sectionWindows {
                sectionWindow.sectionConfig = sectionConfigs[sectionWindow.sectionConfig.number!]!
            }
        }
    }

    let layoutWindow: LayoutWindow

    var gridConfig: GridConfig?
    var gridLayoutWindow: GridLayoutWindow?

    init(name: String, sectionConfigs: [SectionConfig]) {
        self.name = name
        self.layoutType = .zone
        self.sectionConfigs = [:]
        self.gridConfig = nil

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
        self.gridLayoutWindow = nil
    }

    init(name: String, gridConfig: GridConfig) {
        self.name = name
        self.layoutType = .grid
        self.gridConfig = gridConfig
        self.sectionConfigs = [:]
        self.layoutWindow = LayoutWindow(name: name, sectionConfigs: [])
        self.gridLayoutWindow = GridLayoutWindow(name: name, gridConfig: gridConfig)
    }

    func reArrange() {
        guard layoutType == .zone else { return }

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
            sectionWindow.isHovered = false
            sectionWindow.window.orderOut(nil)
            sectionWindow.editorWindow.orderOut(nil)
        }

        layoutWindow.window.orderOut(nil)

        for sectionResizer in layoutWindow.sectionResizers {
            sectionResizer.orderOut(nil)
        }

        gridLayoutWindow?.hide()
    }

    func show(showLayouts: Bool = true, showSnapresizers: Bool = false) {
        switch layoutType {
        case .zone:
            layoutWindow.show(showLayouts: showLayouts, showSnapResizers: showSnapresizers)
        case .grid:
            gridLayoutWindow?.show()
        }
    }

    func hide() {
        switch layoutType {
        case .zone:
            layoutWindow.hide()
        case .grid:
            gridLayoutWindow?.hide()
        }
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

struct LayoutData: Codable {
    var layoutType: LayoutType
    var sectionConfigs: [SectionConfig]?
    var gridConfig: GridConfig?
}

struct UserLayoutsData: Codable {
    var version: Int = 2
    var layouts: [String: LayoutData]
}

class UserLayouts: UserData, ObservableObject {
    @Published var layouts: [String: UserLayout] = [:]
    
    var splitScreenLayout: UserLayout {
        .init(name: "Split Screen", sectionConfigs: [
            .init(number: 1, widthPercentage: 0.5, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Left Half"),
            .init(number: 2, widthPercentage: 0.5, heightPercentage: 1.0, xPercentage: 0.5, yPercentage: 0.0, name: "Right Half"),
            .init(number: 3, widthPercentage: 0.6, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Left 60%"),
            .init(number: 4, widthPercentage: 0.6, heightPercentage: 1.0, xPercentage: 0.4, yPercentage: 0.0, name: "Right 60%"),
            .init(number: 5, widthPercentage: 1.0, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Fullscreen")
        ])
    }
    
    var mainSidebarLayout: UserLayout {
        .init(name: "Main + Sidebar", sectionConfigs: [
            .init(number: 1, widthPercentage: 0.7, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Main 70%"),
            .init(number: 2, widthPercentage: 0.3, heightPercentage: 1.0, xPercentage: 0.7, yPercentage: 0.0, name: "Sidebar 30%"),
            .init(number: 3, widthPercentage: 0.75, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Main 75%"),
            .init(number: 4, widthPercentage: 0.25, heightPercentage: 1.0, xPercentage: 0.75, yPercentage: 0.0, name: "Sidebar 25%"),
            .init(number: 5, widthPercentage: 0.6667, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Main 2/3"),
            .init(number: 6, widthPercentage: 0.3333, heightPercentage: 1.0, xPercentage: 0.6667, yPercentage: 0.0, name: "Sidebar 1/3"),
            .init(number: 7, widthPercentage: 1.0, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Fullscreen")
        ])
    }
    
    var quartersLayout: UserLayout {
        .init(name: "Quarters", sectionConfigs: [
            .init(number: 1, widthPercentage: 0.5, heightPercentage: 0.5, xPercentage: 0.0, yPercentage: 0.0, name: "Top Left"),
            .init(number: 2, widthPercentage: 0.5, heightPercentage: 0.5, xPercentage: 0.5, yPercentage: 0.0, name: "Top Right"),
            .init(number: 3, widthPercentage: 0.5, heightPercentage: 0.5, xPercentage: 0.0, yPercentage: 0.5, name: "Bottom Left"),
            .init(number: 4, widthPercentage: 0.5, heightPercentage: 0.5, xPercentage: 0.5, yPercentage: 0.5, name: "Bottom Right"),
            .init(number: 5, widthPercentage: 0.5, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Left Half"),
            .init(number: 6, widthPercentage: 0.5, heightPercentage: 1.0, xPercentage: 0.5, yPercentage: 0.0, name: "Right Half"),
            .init(number: 7, widthPercentage: 1.0, heightPercentage: 0.5, xPercentage: 0.0, yPercentage: 0.0, name: "Top Half"),
            .init(number: 8, widthPercentage: 1.0, heightPercentage: 0.5, xPercentage: 0.0, yPercentage: 0.5, name: "Bottom Half"),
            .init(number: 9, widthPercentage: 1.0, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Fullscreen")
        ])
    }
    
    var focusedLayout: UserLayout {
        .init(name: "Focused", sectionConfigs: [
            .init(number: 1, widthPercentage: 0.7, heightPercentage: 0.85, xPercentage: 0.15, yPercentage: 0.075, name: "Large Focus"),
            .init(number: 2, widthPercentage: 0.6, heightPercentage: 0.75, xPercentage: 0.2, yPercentage: 0.125, name: "Medium Focus"),
            .init(number: 3, widthPercentage: 0.5, heightPercentage: 0.65, xPercentage: 0.25, yPercentage: 0.175, name: "Small Focus"),
            .init(number: 4, widthPercentage: 1.0, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Fullscreen Focus")
        ])
    }
    
    var tripleColumnLayout: UserLayout {
        .init(name: "Triple Column", sectionConfigs: [
            .init(number: 1, widthPercentage: 0.3333, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Left 1/3"),
            .init(number: 2, widthPercentage: 0.3333, heightPercentage: 1.0, xPercentage: 0.3333, yPercentage: 0.0, name: "Center 1/3"),
            .init(number: 3, widthPercentage: 0.3333, heightPercentage: 1.0, xPercentage: 0.6667, yPercentage: 0.0, name: "Right 1/3"),
            .init(number: 4, widthPercentage: 0.6667, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Left 2/3"),
            .init(number: 5, widthPercentage: 0.6667, heightPercentage: 1.0, xPercentage: 0.3333, yPercentage: 0.0, name: "Right 2/3"),
            .init(number: 6, widthPercentage: 1.0, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Fullscreen")
        ])
    }
    
    var productivityLayout: UserLayout {
        .init(name: "Productivity", sectionConfigs: [
            .init(number: 1, widthPercentage: 0.65, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Main 65%"),
            .init(number: 2, widthPercentage: 0.7, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Main 70%"),
            .init(number: 3, widthPercentage: 0.35, heightPercentage: 0.5, xPercentage: 0.65, yPercentage: 0.0, name: "Top Right"),
            .init(number: 4, widthPercentage: 0.35, heightPercentage: 0.5, xPercentage: 0.65, yPercentage: 0.5, name: "Bottom Right"),
            .init(number: 5, widthPercentage: 0.35, heightPercentage: 1.0, xPercentage: 0.65, yPercentage: 0.0, name: "Right Full"),
            .init(number: 6, widthPercentage: 0.3, heightPercentage: 1.0, xPercentage: 0.7, yPercentage: 0.0, name: "Right Narrow"),
            .init(number: 7, widthPercentage: 1.0, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Fullscreen")
        ])
    }
    
    var ultrawideLayout: UserLayout {
        .init(name: "Ultrawide", sectionConfigs: [
            .init(number: 1, widthPercentage: 0.2, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Left Panel"),
            .init(number: 2, widthPercentage: 0.6, heightPercentage: 1.0, xPercentage: 0.2, yPercentage: 0.0, name: "Center Main"),
            .init(number: 3, widthPercentage: 0.2, heightPercentage: 1.0, xPercentage: 0.8, yPercentage: 0.0, name: "Right Panel"),
            .init(number: 4, widthPercentage: 0.8, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Left + Center"),
            .init(number: 5, widthPercentage: 0.8, heightPercentage: 1.0, xPercentage: 0.2, yPercentage: 0.0, name: "Center + Right"),
            .init(number: 6, widthPercentage: 0.7, heightPercentage: 1.0, xPercentage: 0.15, yPercentage: 0.0, name: "Wide Center"),
            .init(number: 7, widthPercentage: 1.0, heightPercentage: 1.0, xPercentage: 0.0, yPercentage: 0.0, name: "Fullscreen")
        ])
    }
    
    var defaultLayout: UserLayout {
        splitScreenLayout
    }
    
    @Published var currentLayoutName: String = "Split Screen"
    
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
            // Try new versioned format first
            if let layoutsData = try? JSONDecoder().decode(UserLayoutsData.self, from: jsonData) {
                for (name, layoutData) in layoutsData.layouts {
                    switch layoutData.layoutType {
                    case .zone:
                        if let configs = layoutData.sectionConfigs {
                            layouts[name] = .init(name: name, sectionConfigs: configs)
                        }
                    case .grid:
                        if let gridConfig = layoutData.gridConfig {
                            layouts[name] = .init(name: name, gridConfig: gridConfig)
                        }
                    }
                }
            } else {
                let layoutConfigs = try JSONDecoder().decode([String:[SectionConfig]].self, from: jsonData)

                for (layoutName, sectionConfigs) in layoutConfigs {
                    layouts[layoutName] = .init(name: layoutName, sectionConfigs: sectionConfigs)
                }
            }

            if layouts.isEmpty {
                layouts["Split Screen"] = splitScreenLayout
                layouts["Main + Sidebar"] = mainSidebarLayout
                layouts["Quarters"] = quartersLayout
                layouts["Focused"] = focusedLayout
                layouts["Triple Column"] = tripleColumnLayout
                layouts["Productivity"] = productivityLayout
                layouts["Ultrawide"] = ultrawideLayout
                currentLayoutName = "Split Screen"
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
            var layoutsData = UserLayoutsData(version: 2, layouts: [:])

            for (name, layout) in layouts {
                switch layout.layoutType {
                case .zone:
                    layoutsData.layouts[name] = LayoutData(
                        layoutType: .zone,
                        sectionConfigs: Array(layout.sectionConfigs.values)
                    )
                case .grid:
                    layoutsData.layouts[name] = LayoutData(
                        layoutType: .grid,
                        gridConfig: layout.gridConfig
                    )
                }
            }

            let jsonData = try JSONEncoder().encode(layoutsData)
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
            currentLayoutName = "Split Screen"
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
            layout.gridLayoutWindow?.hide()
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

    func createGridLayout(name: String, rows: Int, columns: Int) {
        stopEditing()
        currentLayout.hideAllWindows()

        if layouts.keys.contains(name) { return }

        let gridConfig = GridConfig(rows: rows, columns: columns)
        let newLayout = UserLayout(name: name, gridConfig: gridConfig)
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
            layout.gridLayoutWindow?.name = newName

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
            let duplicatedLayout: UserLayout

            switch currentLayout.layoutType {
            case .zone:
                let sectionConfigs = Array(currentLayout.sectionConfigs.values)
                duplicatedLayout = UserLayout(name: newName, sectionConfigs: sectionConfigs)
            case .grid:
                let gridConfig = currentLayout.gridConfig ?? GridConfig.defaultGrid
                duplicatedLayout = UserLayout(name: newName, gridConfig: gridConfig)
            }

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
