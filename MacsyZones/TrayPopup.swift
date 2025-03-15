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

import SwiftUI
import ServiceManagement

struct AppSettingsData: Codable {
    var modifierKey: String
    var snapKey: String
    var modifierKeyDelay: Int
    var fallbackToPreviousSize: Bool
    var onlyFallbackToPreviousSizeWithUserEvent: Bool
    var selectPerDesktopLayout: Bool
    var prioritizeCenterToSnap: Bool
    var shakeToSnap: Bool
    var shakeAccelerationThreshold: CGFloat
    var snapResize: Bool
    var snapResizeThreshold: CGFloat
    var quickSnapShortcut: String
    var snapWithRightClick: Bool
}

class AppSettings: UserData, ObservableObject {
    @Published var modifierKey: String = "Control"
    @Published var snapKey: String = "Shift"
    @Published var modifierKeyDelay: Int = 500
    @Published var fallbackToPreviousSize: Bool = true
    @Published var onlyFallbackToPreviousSizeWithUserEvent: Bool = true
    @Published var selectPerDesktopLayout: Bool = true
    @Published var prioritizeCenterToSnap: Bool = true
    @Published var shakeToSnap: Bool = true
    @Published var shakeAccelerationThreshold: CGFloat = 55000.0
    @Published var snapResize: Bool = true
    @Published var snapResizeThreshold: CGFloat = 33.0
    @Published var quickSnapShortcut: String = "Control+Shift+S"
    @Published var snapWithRightClick: Bool = true

    init() {
        super.init(name: "AppSettings", data: "{}", fileName: "AppSettings.json")
    }

    override func load() {
        super.load()

        let jsonData = data.data(using: .utf8)!
        
        do {
            let settings = try JSONDecoder().decode(AppSettingsData.self, from: jsonData)
            
            self.modifierKey = settings.modifierKey
            self.snapKey = settings.snapKey
            self.modifierKeyDelay = settings.modifierKeyDelay
            self.fallbackToPreviousSize = settings.fallbackToPreviousSize
            self.onlyFallbackToPreviousSizeWithUserEvent = settings.onlyFallbackToPreviousSizeWithUserEvent
            self.selectPerDesktopLayout = settings.selectPerDesktopLayout
            self.prioritizeCenterToSnap = settings.prioritizeCenterToSnap
            self.shakeToSnap = settings.shakeToSnap
            self.shakeAccelerationThreshold = settings.shakeAccelerationThreshold
            self.snapResize = settings.snapResize
            self.snapResizeThreshold = settings.snapResizeThreshold
            self.quickSnapShortcut = settings.quickSnapShortcut
            self.snapWithRightClick = settings.snapWithRightClick
        } catch {
            print("Error parsing settings JSON: \(error)")
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
                snapWithRightClick: snapWithRightClick
            )
            
            let jsonData = try JSONEncoder().encode(settings)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                data = jsonString
                super.save()
            }
        } catch {
            print("Error encoding settings JSON: \(error)")
        }
    }
}

let appSettings = AppSettings()

import SwiftUI

struct ShortcutInputView: View {
    @Binding var shortcut: String
    @State private var isListening = false
    @State private var flagsMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var currentModifiers: NSEvent.ModifierFlags = []

    var body: some View {
        VStack {
            Button(action: {
                toggleListening()
            }) {
                Text(isListening ? "Listening for shortcut..." : shortcut.isEmpty ? "Click to set shortcut" : shortcut)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .cornerRadius(7)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isListening ? Color(NSColor.selectedTextBackgroundColor).opacity(0.2) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isListening ? Color(NSColor.selectedTextBackgroundColor) : Color.gray, lineWidth: 1)
            )
        }
        .onDisappear {
            stopListening()
        }
    }
    
    private func toggleListening() {
        isListening.toggle()
        if isListening {
            startListening()
        } else {
            stopListening()
        }
    }

    private func startListening() {
        isListening = true
        
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            self.currentModifiers = event.modifierFlags
            return event
        }
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                self.stopListening()
                return nil
            }
            
            let keyString: String
            switch event.keyCode {
            case 48: keyString = "Tab"
            case 36: keyString = "Return"
            case 51: keyString = "Delete"
            case 123: keyString = "Left"
            case 124: keyString = "Right"
            case 125: keyString = "Down"
            case 126: keyString = "Up"
            case 49: keyString = "Space"
            default:
                keyString = event.charactersIgnoringModifiers?.uppercased() ?? ""
            }
            
            var components = [String]()
            
            if self.currentModifiers.contains(.command) {
                components.append("Command")
            }
            if self.currentModifiers.contains(.option) {
                components.append("Option")
            }
            if self.currentModifiers.contains(.control) {
                components.append("Control")
            }
            if self.currentModifiers.contains(.shift) {
                components.append("Shift")
            }
            
            if !keyString.isEmpty {
                components.append(keyString)
            }
            
            self.shortcut = components.joined(separator: "+")
            self.stopListening()
            return nil
        }
    }

    private func stopListening() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        flagsMonitor = nil
        keyMonitor = nil
        currentModifiers = []
        isListening = false
    }

    private func createShortcutString(from event: NSEvent) -> String {
        var components = [String]()

        if event.modifierFlags.contains(.command) {
            components.append("Command")
        }
        if event.modifierFlags.contains(.option) {
            components.append("Option")
        }
        if event.modifierFlags.contains(.control) {
            components.append("Control")
        }
        if event.modifierFlags.contains(.shift) {
            components.append("Shift")
        }

        if let characters = event.charactersIgnoringModifiers {
            components.append(characters.uppercased())
        }

        return components.joined(separator: "+")
    }
}

struct Main: View {
    @State var proLock: ProLock
    
    @Binding var page: String
    
    @ObservedObject var settings = appSettings
    
    @ObservedObject var layouts = userLayouts
    
    @State var showNotProDialog: Bool = false
    @State var showAboutDialog: Bool = false
    
    @State var showDialog: Bool = false
    @State var showLayoutHelpDialog: Bool = false
    @State var showModifierKeyHelpDialog: Bool = false
    @State var showSnapKeyHelpDialog: Bool = false
    @State var showQuickSnapperHelpDialog: Bool = false
    @State var showSnapResizeHelpDialog: Bool = false
    
    func resetDialogs() {
        showDialog = false
        showLayoutHelpDialog = false
        showModifierKeyHelpDialog = false
        showSnapKeyHelpDialog = false
        showQuickSnapperHelpDialog = false
        showSnapResizeHelpDialog = false
    }
    
    @State private var startAtLogin = false
    
    @ObservedObject var updater = appUpdater
    
    func toggleRunAtStartup() {
        if #available(macOS 13.0, *) {
            do {
                if startAtLogin {
                    try SMAppService.mainApp.unregister()
                    startAtLogin = false
                } else {
                    try SMAppService.mainApp.register()
                    startAtLogin = true
                }
            } catch {
                print("Failed to toggle run at startup: \(error)")
                startAtLogin = false
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .center) {
            HStack(alignment: .center, spacing: 5) {
                if proLock.isPro {
                    Text("MacsyZones Pro").font(.headline)
                } else {
                    Text("MacsyZones").font(.headline)
                }
                
                Button(action: {
                    resetDialogs()
                    showDialog = true
                    showAboutDialog = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.bottom, 10)

            HStack(alignment: .center, spacing: 5) {
                Text("Layouts").font(.subheadline)
                
                Button(action: {
                    resetDialogs()
                    showDialog = true
                    showLayoutHelpDialog = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            
            if #available(macOS 14.0, *) {
                Picker("Select Layout", selection: $layouts.currentLayoutName) {
                    ForEach(Array(layouts.layouts.keys), id: \.self) { name in
                        Text(name)
                    }
                }.onAppear {
                    if let preferedLayout = spaceLayoutPreferences.getCurrent() {
                        layouts.currentLayoutName = preferedLayout
                    }
                }.onChange(of: layouts.currentLayoutName) {
                    let wasEditing = isEditing
                    stopEditing()
                    userLayouts.selectLayout(layouts.currentLayoutName)
                    if wasEditing {
                        startEditing()
                    }
                    
                    spaceLayoutPreferences.setCurrent(layoutName: layouts.currentLayoutName)
                    spaceLayoutPreferences.save()
                }.labelsHidden()
                    .pickerStyle(MenuPickerStyle())
                    .padding(.bottom, 5)
            } else {
                Picker("Select Layout", selection: $layouts.currentLayoutName) {
                    ForEach(Array(layouts.layouts.keys), id: \.self) { name in
                        Text(name)
                    }
                }.labelsHidden()
                 .pickerStyle(MenuPickerStyle())
                 .padding(.bottom, 5)
                 .onAppear {
                     if let preferedLayout = spaceLayoutPreferences.getCurrent() {
                         layouts.currentLayoutName = preferedLayout
                     }
                 }
                 .onChange(of: layouts.currentLayoutName) { _ in
                     let wasEditing = isEditing
                     stopEditing()
                     userLayouts.selectLayout(layouts.currentLayoutName)
                     if wasEditing {
                         startEditing()
                     }
                 
                     spaceLayoutPreferences.setCurrent(layoutName: layouts.currentLayoutName)
                     spaceLayoutPreferences.save()
                 }
            }
            
            HStack {
                Button(action: {
                    toggleEditing()
                }) {
                    HStack {
                        Image(systemName: "pencil")
                    }
                }
                Button(action: {
                    stopEditing()
                    page = "rename"
                }) {
                    HStack {
                        Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    }
                }
                Button(action: {
                    stopEditing()
                    page = "new"
                }) {
                    HStack {
                        Image(systemName: "plus")
                    }
                }
                Button(action: {
                    layouts.removeCurrentLayout()
                }) {
                    HStack {
                        Image(systemName: "trash")
                    }
                }.disabled(layouts.layouts.count < 2)
            }.padding(.bottom, 5)

            Divider()

            HStack(alignment: .center, spacing: 5) {
                Text("Modifier Key").font(.subheadline)
                
                Button(action: {
                    resetDialogs()
                    showDialog = true
                    showModifierKeyHelpDialog = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .font(.subheadline)
            .padding(.top, 5)
            
            Picker("Modifier Key", selection: $settings.modifierKey) {
                Text("None").tag("None")
                Text("Command").tag("Command")
                Text("Option").tag("Option")
                Text("Control").tag("Control")
            }
            .labelsHidden()
            .pickerStyle(MenuPickerStyle())
            .padding(.bottom, 5)
            .onChange(of: settings.modifierKey) { _ in
                appSettings.save()
            }
            
            Text("Long Press Delay: \(String(format: "%.2f", Double(settings.modifierKeyDelay) / 1000.0)) secs")
                .font(.subheadline).padding(.bottom, 2)
            Slider(value: Binding(
                get: { Double(settings.modifierKeyDelay) },
                set: { settings.modifierKeyDelay = Int($0) }
            ), in: 0...2000, step: 100)
            .frame(alignment: .center)
            .padding(.bottom, 5)
            .onChange(of: settings.modifierKeyDelay) { _ in
                appSettings.save()
            }
            
            Divider()
            
            HStack(alignment: .center, spacing: 5) {
                Text("Snap Key").font(.subheadline)
                
                Button(action: {
                    resetDialogs()
                    showDialog = true
                    showSnapKeyHelpDialog = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .font(.subheadline)
            .padding(.top, 5)
            
            Picker("Snap Key", selection: $settings.snapKey) {
                Text("None").tag("None")
                Text("Shift").tag("Shift")
                Text("Command").tag("Command")
                Text("Option").tag("Option")
                Text("Control").tag("Control")
            }
            .labelsHidden()
            .pickerStyle(MenuPickerStyle())
            .padding(.bottom, 5)
            .onChange(of: settings.snapKey) { _ in
                appSettings.save()
            }
            
            Toggle("Snap with right click", isOn: $settings.snapWithRightClick)
            .onChange(of: settings.snapWithRightClick) { _ in
                appSettings.save()
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 5)
            
            Divider()
            
            HStack(alignment: .center, spacing: 5) {
                Text("Quick Snapper Shortcut").font(.subheadline)
                
                Button(action: {
                    resetDialogs()
                    showDialog = true
                    showQuickSnapperHelpDialog = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
                .font(.subheadline)
                .padding(.top, 5).padding(.bottom, 5)
            
            ShortcutInputView(shortcut: $settings.quickSnapShortcut).onChange(of: settings.quickSnapShortcut) { _ in
                appSettings.save()
            }.padding(.bottom, 5)

            Divider()
            
            Text("Options").font(.subheadline).padding(.top, 5)
            
            HStack {
                Toggle("Enable snap resizing", isOn: $settings.snapResize)
                .onChange(of: settings.snapResize) { _ in
                    appSettings.save()
                }
                
                Button(action: {
                    resetDialogs()
                    showDialog = true
                    showSnapResizeHelpDialog = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
                
                Spacer()
            }.padding(.bottom, 5)
            
            if settings.snapResize {
                Text("Snap Threshold: \(Int(settings.snapResizeThreshold))px")
                    .font(.subheadline)
                Slider(value: Binding(
                    get: { Double(settings.snapResizeThreshold) },
                    set: { settings.snapResizeThreshold = CGFloat($0) }
                ), in: 5...67, step: 2)
                .frame(alignment: .center)
                .onChange(of: settings.snapResizeThreshold) { _ in
                    appSettings.save()
                }
                
                Divider().padding(.bottom, 5)
            }
            
            HStack {
                Toggle("Prioritize section center", isOn: $settings.prioritizeCenterToSnap)
                .onChange(of: settings.prioritizeCenterToSnap) { _ in
                    appSettings.save()
                }
                Spacer()
            }.padding(.bottom, 5)
            
            Divider()

            HStack {
                Toggle("Fallback to previous size", isOn: $settings.fallbackToPreviousSize)
                .onChange(of: settings.fallbackToPreviousSize) { _ in
                    appSettings.save()
                }
                Spacer()
            }.padding(.bottom, 5)
            if settings.fallbackToPreviousSize {
                HStack {
                    Toggle("Only with user event", isOn: $settings.onlyFallbackToPreviousSizeWithUserEvent)
                    .onChange(of: settings.onlyFallbackToPreviousSizeWithUserEvent) { _ in
                        appSettings.save()
                    }
                    Spacer()
                }.padding(.bottom, 5)
                
                Divider()
            }
            
            HStack {
                Toggle("Select per-desktop layout", isOn: $settings.selectPerDesktopLayout)
                .onChange(of: settings.selectPerDesktopLayout) { _ in
                    appSettings.save()
                }
                Spacer()
            }.padding(.bottom, 5)
            HStack {
                Toggle("Shake to snap", isOn: $settings.shakeToSnap)
                .onChange(of: settings.shakeToSnap) { _ in
                    appSettings.save()
                }
                Spacer()
            }.padding(.bottom, 5)
            
            if settings.shakeToSnap {
                VStack {
                    Text("Shake Hardness").font(.subheadline)
                    Slider(value: Binding(
                        get: { Double(settings.shakeAccelerationThreshold) },
                        set: { settings.shakeAccelerationThreshold = CGFloat($0) }
                    ), in: 10000...110000, step: 10000)
                    .onChange(of: settings.shakeAccelerationThreshold) { _ in
                        appSettings.save()
                    }
                }
                .padding(.bottom, 10)
            }
            
            if #available(macOS 14.0, *) {
                HStack {
                    Toggle("Start at login", isOn: $startAtLogin)
                        .onChange(of: startAtLogin) { oldValue, newValue in
                            if oldValue != newValue {
                                do {
                                    if startAtLogin {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try SMAppService.mainApp.unregister()
                                    }
                                } catch {
                                    print("Failed to toggle run at startup: \(error)")
                                    startAtLogin = false
                                }
                            }
                        }
                        .onAppear {
                            startAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    Spacer()
                }.padding(.bottom, 5)
            } else if #available(macOS 13.0, *) {
                HStack {
                    Toggle("Start at login", isOn: $startAtLogin)
                        .onChange(of: startAtLogin) { value in
                            toggleRunAtStartup()
                        }
                        .onAppear {
                            startAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    Spacer()
                }.padding(.bottom, 5)
            }

            #if !APPSTORE
                if !proLock.isPro {
                    Divider()
                    
                    Button(action: {
                        page = "unlock"
                    }) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                            Text("Unlock Pro Version")
                                .fontWeight(.bold)
                        }
                    }.padding()
                     .frame(maxWidth: .infinity)
                     .background(Color.pink.opacity(0.2))
                     .cornerRadius(7)
                     .alert(isPresented: $showNotProDialog) {
                         Alert(
                             title: Text("Omg! 😊"),
                             message: Text("You must buy MacsyZones Pro to unlock this feature."),
                             dismissButton: .default(Text("OK"))
                         )
                     }
                }
            #endif
            
            Divider()
            
            VStack(alignment: .center) {
                Button(action: {
                    updater.checkForUpdates()
                }) {
                    HStack {
                        if updater.isChecking {
                            Image(systemName: "arrow.clockwise.circle")
                            Text("Checking for Updates...")
                        } else if updater.isDownloading {
                            ProgressView()
                                .font(.system(size: 12))
                            Text("Downloading Update...")
                        } else if let isUpdatable = updater.isUpdatable,
                                  let latestVersion = updater.latestVersion,
                                  isUpdatable
                        {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Update to \(latestVersion)")
                        } else {
                            Image(systemName: "arrow.clockwise.circle")
                            Text("Check for Updates")
                        }
                    }
                }
                .disabled(updater.isChecking || updater.isDownloading)
            }
            .padding(.vertical, 10)
            
            Divider()

            Button(action: {
                NSApp.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit MacsyZones")
                }
            }
        }.padding()
         .frame(width: 240)
         .alert(isPresented: $showDialog) {
             if showLayoutHelpDialog {
                 return Alert(
                    title: Text("Layouts"),
                    message: Text("""
                    You can add, remove, rename layouts and select a layout for your current (screen, workspace) pair.
                
                    MacsyZones will remember the layout you selected for each (screen, workspace) pair.
                
                    Important: Please do NOT place your zones on multiple screens while you are editing a layout. It is an undefined behavior for MacsyZones so far.
                
                    Instead, you can create many layouts for each screen (or workspace) and switch between them easily; MacsyZones will remember the layout you selected for each (screen, workspace) pair.
                
                    Enjoy! 🥳
                """),
                    dismissButton: .default(Text("OK"))
                 )
             } else if showModifierKeyHelpDialog {
                 return Alert(
                    title: Text("Modifier Key"),
                    message: Text("""
                        Modifier key is mainly for performing snap resize but you can also use it to snap your windowst to your zones.
                    
                        Modifier key has a delay that you can adjust; when you press and hold the modifier key, MacsyZones will start to show you the zones with snap resizers between them.
                    
                        You can hold the modifier key and perform snap resizing with your mouse or trackpad.
                        
                        Enjoy! 🥳
                    """),
                    dismissButton: .default(Text("OK"))
                 )
             } else if showSnapKeyHelpDialog {
                 return Alert(
                    title: Text("Snap Key"),
                    message: Text("""
                        Snap key is for snapping your windows to your zones.
                    
                        You can hold the snap key and drag your windows to the zones.
                    
                        Snap key works only while you are moving a window.
                    
                        Enjoy! 🥳
                    """),
                    dismissButton: .default(Text("OK"))
                 )
            } else if showQuickSnapperHelpDialog {
                return Alert(
                    title: Text("Quick Snap Shortcut"),
                    message: Text("""
                        Quick Snap shortcut is for activating the Quick Snapper. 
                        
                        Quick Snapper is a feature that allows you to snap your windows to your zones with your keyboard easily and very quickly.
                    
                        It is also useful as a window switcher. (Like Windows' Alt+Tab window switcher.)
                        
                        Enjoy! 🥳
                    """),
                    dismissButton: .default(Text("OK"))
                 )
            } else if showSnapResizeHelpDialog {
                return Alert(
                   title: Text("Snap Resize"),
                   message: Text("""
                       Snap resizing is a feature that allows you to resize your windows to your zones.
                       
                       You can enable or disable snap resizing and adjust the snap threshold.
                   
                       Modifier key has a delay that you can adjust; when you press and hold the modifier key, MacsyZones will start to show you the zones with snap resizers between them.
                   
                       You can hold the modifier key and perform snap resizing with your mouse or trackpad.
                       
                       Enjoy! 🥳
                   """),
                   dismissButton: .default(Text("OK"))
                )
             } else {
                 let licenseInfo = proLock.isPro ? "\nLicensed for: \(proLock.owner ?? "Unknown User")" : "(Free version)"
                 
                 return Alert(
                     title: Text("About MacsyZones"),
                     message: Text("""
                         Copyright ©️ 2024, Oğuzhan Eroğlu (https://meowingcat.io).
                         
                         MacsyZones helps you organize your windows efficiently.
                         
                         Version: \(appVersion) (Build: \(appBuild))
                         \(licenseInfo)
                     """),
                     primaryButton: .default(Text("Visit Website")) {
                         if let url = URL(string: "https://macsyzones.com") {
                             NSWorkspace.shared.open(url)
                         }
                     },
                     secondaryButton: .cancel(Text("OK"))
                 )
             }
         }
    }
}

struct NewView: View {
    @Binding var page: String
    @ObservedObject var layouts = userLayouts

    @State var layoutName: String = "My Layout"
    
    @State var showAlreadyExistsAlert: Bool = false
    
    var body: some View {
        VStack {
            Text("MacsyZones").font(.headline).padding(.bottom, 10)
            
            Text("Layout Name:").font(.subheadline)
            
            VStack {
                TextField("Enter Layout Name", text: $layoutName).cornerRadius(5)
                
                HStack(alignment: .center) {
                    Button(action: {
                        page = "main"
                    }) {
                        Image(systemName: "xmark").foregroundColor(.red)
                        Text("Cancel")
                    }
                    
                    Button(action: {
                        if layouts.layouts.keys.contains(layoutName) {
                            showAlreadyExistsAlert = true
                            return
                        }
                        
                        layouts.createLayout(name: layoutName)
                        startEditing()
                        
                        page = "main"
                    }) {
                        Image(systemName: "checkmark").foregroundColor(.green)
                        Text("Create")
                    }
                }
            }
        }.padding()
            .alert(isPresented: $showAlreadyExistsAlert) {
                Alert(
                    title: Text("Omg! 😊"),
                    message: Text("Another layout with this name already exists. Please choose another name."),
                    dismissButton: .default(Text("OK"))
                )
            }
    }
}

struct RenameView: View {
    @Binding var page: String
    @ObservedObject var layouts = userLayouts
    
    @State var layoutName: String = ""
    
    var body: some View {
        VStack {
            Text("MacsyZones").font(.headline).padding(.bottom, 10)
            
            Text("Layout Name:").font(.subheadline)
            
            VStack {
                TextField("Enter Layout Name", text: $layoutName).cornerRadius(5)
                
                HStack(alignment: .center) {
                    Button(action: {
                        page = "main"
                    }) {
                        Image(systemName: "xmark").foregroundColor(.red)
                        Text("Cancel")
                    }
                    
                    Button(action: {
                        userLayouts.renameCurrentLayout(to: layoutName)
                        page = "main"
                    }) {
                        Image(systemName: "checkmark").foregroundColor(.green)
                        Text("Rename")
                    }
                }
            }
        }.padding()
    }
}

struct UnlockProView: View {
    @State var proLock: ProLock
    
    @Binding var page: String
    @State private var licenseKey: String = ""
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack {
            Text("Unlock Pro Version").font(.headline).padding(.bottom, 10)
            
            Text("Enter your License Key").font(.subheadline)
            
            VStack {
                if #available(macOS 14.0, *) {
                    TextField("Enter License Key", text: $licenseKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.bottom, 10)
                        .onChange(of: licenseKey) { oldValue, newValue in
                            errorMessage = nil
                        }
                } else {
                    TextField("Enter License Key", text: $licenseKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.bottom, 10)
                        .onChange(of: licenseKey) { _ in
                            errorMessage = nil
                        }
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.bottom, 10)
                }
                
                HStack(alignment: .center) {
                    Button(action: {
                        page = "main"
                    }) {
                        Image(systemName: "xmark").foregroundColor(.red)
                        Text("Cancel")
                    }
                    
                    Button(action: {
                        if validateLicenseKey(licenseKey) {
                            unlockProVersion(with: licenseKey)
                            page = "main"
                        } else {
                            errorMessage = "Invalid License Key. Please try again."
                        }
                    }) {
                        Image(systemName: "checkmark").foregroundColor(.green)
                        Text("Unlock")
                    }
                }
                .padding(.bottom, 10)
                
                Button(action: {
                    openPurchaseLink()
                }) {
                    Image(systemName: "cart").foregroundColor(.blue)
                    Text("Buy Pro License Key")
                }
            }
        }.frame(minWidth: 300)
         .padding()
    }
    
    func validateLicenseKey(_ key: String) -> Bool {
        return proLock.setLicenseKey(key)
    }
    
    func unlockProVersion(with key: String) {
        print("Pro version unlocked 🥳")
    }
    
    func openPurchaseLink() {
        if let url = URL(string: "https://macsyzones.com/") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct TrayPopupView: View {
    @ObservedObject var ready = macsyReady
    @ObservedObject var proLock = macsyProLock
    
    @State private var page = "main"
    @ObservedObject var layouts = userLayouts
    
    var body: some View {
        if !ready.isReady {
            VStack {
                VStack(alignment: .center) {
                    Text("MacsyZones is loading...").padding(.bottom, 10).padding(.top, 25)
                    ProgressView().padding(.bottom, 25)
                }.frame(width: 240)
            }
        } else {
            VStack {
                switch page {
                case "new":
                    NewView(page: $page)
                case "rename":
                    RenameView(page: $page, layoutName: layouts.currentLayoutName)
                case "unlock":
                    UnlockProView(proLock: proLock, page: $page)
                default:
                    Main(proLock: proLock, page: $page)
                }
            }
        }
    }
}

#Preview {
    TrayPopupView(layouts: UserLayouts())
}
