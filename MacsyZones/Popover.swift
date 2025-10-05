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
import Combine

class PopoverState: ObservableObject {
    static let shared = PopoverState()
    @Published var shouldStopListening = false
}

struct ShortcutInputView: View {
    @Binding var shortcut: String
    var isFocused: Binding<Bool> = .constant(false)
    
    @State private var isListening = false
    @State private var flagsMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var currentModifiers: NSEvent.ModifierFlags = []
    @ObservedObject private var popoverState = PopoverState.shared

    var body: some View {
        Button(action: {
            toggleListening()
        }) {
            VStack {
                Text(isListening ? "Listening for shortcut..." : shortcut.isEmpty ? "Click to set shortcut" : presentingShortcut(shortcut))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .cornerRadius(7)
            }
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
        .buttonStyle(PlainButtonStyle())
        .onDisappear {
            stopListening()
            isFocused.wrappedValue = false
        }
        .onChange(of: isListening) { newValue in
            isFocused.wrappedValue = newValue
        }
        .onChange(of: popoverState.shouldStopListening) { shouldStop in
            if shouldStop && isListening {
                stopListening()
            }
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
            let keyString: String
            switch event.keyCode {
            case 48: keyString = "Tab"
            case 36: keyString = "Return"
            case 51: keyString = "Delete"
            case 53: keyString = "Escape"
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
    
    @State var showNotProDialog = false
    @State var showAboutDialog = false
    
    @State var showDialog = false
    @State var showLayoutHelpDialog = false
    @State var showModifierKeyHelpDialog = false
    @State var showSnapKeyHelpDialog = false
    @State var showQuickSnapperHelpDialog = false
    @State var showSnapResizeHelpDialog = false
    @State var showWindowCyclingHelpDialog = false
    @State var showSnapHighlightStrategyHelpDialog = false
    @State var showPerDesktopLayoutsHelpDialog = false
    
    func resetDialogs() {
        showDialog = false
        showLayoutHelpDialog = false
        showModifierKeyHelpDialog = false
        showSnapKeyHelpDialog = false
        showQuickSnapperHelpDialog = false
        showSnapResizeHelpDialog = false
        showWindowCyclingHelpDialog = false
        showSnapHighlightStrategyHelpDialog = false
        showPerDesktopLayoutsHelpDialog = false
    }
    
    func sensitivityLabel(for threshold: CGFloat) -> String {
        let minSensitivity: CGFloat = 10000
        let maxSensitivty: CGFloat = 100000
        let levels = ["Very High", "High", "Medium", "Low"]
        
        let relative = threshold - minSensitivity
        let level = Int((relative / CGFloat(maxSensitivty - minSensitivity)) * CGFloat(levels.count))
        let index = max(0, min(level, levels.count - 1))
        
        return levels[index]
    }
    
    @State private var startAtLogin = false
    
    @ObservedObject var updater = appUpdater
    
    func updateStartAtLoginState() {
        if #available(macOS 13.0, *) {
            let actualState = SMAppService.mainApp.status == .enabled
            
            if startAtLogin != actualState {
                startAtLogin = actualState
                debugLog("Updated start at login state to: \(actualState)")
            }
        }
    }
    
    func toggleRunAtStartup() {
        if #available(macOS 13.0, *) {
            do {
                if startAtLogin {
                    try SMAppService.mainApp.register()
                    debugLog("Successfully registered app to start at login")
                } else {
                    try SMAppService.mainApp.unregister()
                    debugLog("Successfully unregistered app from start at login")
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.updateStartAtLoginState()
                }
                
            } catch {
                debugLog("Failed to toggle run at startup: \(error)")
                DispatchQueue.main.async {
                    self.updateStartAtLoginState()
                }
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
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
                        .font(.system(size: 14))
                        .imageScale(.small)
                        .contentShape(Circle())
                }
                .contentShape(Circle())
                .buttonStyle(BorderlessButtonStyle())
                .modifier {
                    if #available(macOS 14.0, *) {
                        $0.focusEffectDisabled(true)
                    } else { $0 }
                }
            }
            .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        HStack(spacing: 5) {
                            Text("Layouts").font(.subheadline)
                            Button(action: {
                                resetDialogs()
                                showDialog = true
                                showLayoutHelpDialog = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .imageScale(.small)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        Picker("Select Layout", selection: $layouts.currentLayoutName) {
                            ForEach(Array(layouts.layouts.keys), id: \.self) { name in
                                Text(name)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .onAppear {
                            if let preferedLayout = spaceLayoutPreferences.getCurrent() {
                                layouts.currentLayoutName = preferedLayout
                            }
                        }
                        .onChange(of: layouts.currentLayoutName) { _ in
                            let wasEditing = isEditing
                            stopEditing()
                            userLayouts.selectLayout(layouts.currentLayoutName)
                            if wasEditing { startEditing() }
                            spaceLayoutPreferences.setCurrent(layoutName: layouts.currentLayoutName)
                            spaceLayoutPreferences.save()
                        }
                        
                        HStack(alignment: .center, spacing: 2) {
                            let buttonHeight: CGFloat = 25
                            
                            Button(action: { toggleEditing() }) {
                                Image(systemName: "pencil")
                                    .frame(height: buttonHeight)
                            }
                            
                            Button(action: { stopEditing(); page = "rename" }) {
                                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                                    .frame(height: buttonHeight)
                            }
                            
                            Button(action: { stopEditing(); page = "new" }) {
                                Image(systemName: "plus")
                                    .frame(height: buttonHeight)
                            }
                            
                            Button(action: { layouts.removeCurrentLayout() }) {
                                Image(systemName: "trash")
                                    .frame(height: buttonHeight)
                            }
                            .disabled(layouts.layouts.count < 2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    Divider().padding(.vertical, 2)
                    
                    Group {
                        HStack(spacing: 5) {
                            Text("Snap Key").font(.subheadline)
                            Button(action: {
                                resetDialogs()
                                showDialog = true
                                showSnapKeyHelpDialog = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .imageScale(.small)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        Picker("Snap Key", selection: $settings.snapKey) {
                            Text("None").tag("None")
                            Text("Shift").tag("Shift")
                            Text("Command").tag("Command")
                            Text("Option").tag("Option")
                            Text("Control").tag("Control")
                        }
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: settings.snapKey) { _ in appSettings.save() }
                        
                        Toggle("Snap with right click", isOn: $settings.snapWithRightClick)
                            .toggleStyle(.checkbox)
                            .onChange(of: settings.snapWithRightClick) { _ in appSettings.save() }
                            .padding(.top, 4)
                    }
                    
                    Divider().padding(.vertical, 2)
                    
                    Group {
                        HStack(spacing: 5) {
                            Text("Modifier Key").font(.subheadline)
                            Button(action: {
                                resetDialogs()
                                showDialog = true
                                showModifierKeyHelpDialog = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .imageScale(.small)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        Picker("Modifier Key", selection: $settings.modifierKey) {
                            Text("None").tag("None")
                            Text("Command").tag("Command")
                            Text("Option").tag("Option")
                            Text("Control").tag("Control")
                        }
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: settings.modifierKey) { _ in appSettings.save() }
                        
                        Text("Delay: \(String(format: "%.2f", Double(settings.modifierKeyDelay) / 1000.0))s")
                            .font(.caption2)
                        Slider(value: Binding(
                            get: { Double(settings.modifierKeyDelay) },
                            set: { settings.modifierKeyDelay = Int($0) }
                        ), in: 0...2000, step: 100)
                        .onChange(of: settings.modifierKeyDelay) { _ in appSettings.save() }
                    }
                    
                    Divider().padding(.vertical, 2)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 5) {
                            Text("Window Cycling").font(.subheadline)
                            Button(action: {
                                resetDialogs()
                                showDialog = true
                                showWindowCyclingHelpDialog = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .imageScale(.small)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Group {
                                Text("Cycle Forward").font(.caption2)
                                ShortcutInputView(shortcut: $settings.cycleWindowsForwardShortcut)
                                    .onChange(of: settings.cycleWindowsForwardShortcut) { newShortcut in
                                        if #available(macOS 12.0, *) {
                                            cycleForwardHotkey.register(for: newShortcut)
                                        }
                                        
                                        appSettings.save()
                                    }
                            }
                            
                            Group {
                                Text("Cycle Backward").font(.caption2)
                                ShortcutInputView(shortcut: $settings.cycleWindowsBackwardShortcut)
                                    .onChange(of: settings.cycleWindowsBackwardShortcut) { newShortcut in
                                        if #available(macOS 12.0, *) {
                                            cycleBackwardHotkey.register(for: newShortcut)
                                        }
                                        
                                        appSettings.save()
                                    }
                            }
                        }
                    }
                }
                .fixedSize()
                
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading) {
                        VStack {
                            HStack(spacing: 5) {
                                Text("Quick Snapper").font(.subheadline)
                                Button(action: {
                                    resetDialogs()
                                    showDialog = true
                                    showQuickSnapperHelpDialog = true
                                }) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 13))
                                        .imageScale(.small)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            ShortcutInputView(shortcut: $settings.quickSnapShortcut)
                                .onChange(of: settings.quickSnapShortcut) { _ in
                                    if #available(OSX 12.0, *) {
                                        quickSnapper.toggleHotkey?.register(for: settings.quickSnapShortcut)
                                    }
                                    
                                    appSettings.save()
                                }
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        Toggle("Snap resize", isOn: $settings.snapResize)
                            .toggleStyle(.checkbox)
                            .onChange(of: settings.snapResize) { _ in appSettings.save() }
                        
                        if settings.snapResize {
                            Text("Threshold: \(Int(settings.snapResizeThreshold))px")
                                .font(.caption2)
                                .padding(.top, 4)
                            
                            Slider(value: Binding(
                                get: { Double(settings.snapResizeThreshold) },
                                set: { settings.snapResizeThreshold = CGFloat($0) }
                            ), in: 5...67, step: 2)
                            .onChange(of: settings.snapResizeThreshold) { _ in appSettings.save() }
                            
                            Toggle("Show snap resizers on hover", isOn: $settings.showSnapResizersOnHover)
                                .toggleStyle(.checkbox)
                                .onChange(of: settings.showSnapResizersOnHover) { _ in appSettings.save() }
                            
                            Divider().padding(.vertical, 2)
                        }
                        
                        Group {
                            Toggle("Prioritize zone center", isOn: $settings.prioritizeCenterToSnap)
                                .toggleStyle(.checkbox)
                                .onChange(of: settings.prioritizeCenterToSnap) { _ in appSettings.save() }
                            
                            HStack(spacing: 5) {
                                Text("Zone Highlighting Strategy").font(.subheadline)
                                    .padding(.top, 4)
                                
                                Button(action: {
                                    resetDialogs()
                                    showDialog = true
                                    showSnapHighlightStrategyHelpDialog = true
                                }) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 13))
                                        .imageScale(.small)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            
                            Picker("Zone Highlighting Strategy", selection: $settings.snapHighlightStrategy) {
                                Text("Center Proximity").tag(SnapHighlightStrategy.centerProximity)
                                Text("Flat").tag(SnapHighlightStrategy.flat)
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .onChange(of: settings.snapKey) { _ in appSettings.save() }
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        Toggle("Fallback previous size when unsnapped", isOn: $settings.fallbackToPreviousSize)
                            .toggleStyle(.checkbox)
                            .onChange(of: settings.fallbackToPreviousSize) { _ in appSettings.save() }
                        
                        if settings.fallbackToPreviousSize {
                            Toggle("Only with user event", isOn: $settings.onlyFallbackToPreviousSizeWithUserEvent)
                                .toggleStyle(.checkbox)
                                .onChange(of: settings.onlyFallbackToPreviousSizeWithUserEvent) { _ in appSettings.save() }
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        HStack {
                            Toggle("Per-desktop layouts", isOn: $settings.selectPerDesktopLayout)
                                .toggleStyle(.checkbox)
                                .onChange(of: settings.selectPerDesktopLayout) { _ in appSettings.save() }
                            
                            Button(action: {
                                resetDialogs()
                                showDialog = true
                                showPerDesktopLayoutsHelpDialog = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .imageScale(.small)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        Toggle("Shake to snap", isOn: $settings.shakeToSnap)
                            .toggleStyle(.checkbox)
                            .onChange(of: settings.shakeToSnap) { _ in appSettings.save() }
                        
                        if settings.shakeToSnap {
                            HStack {
                                Text("Sensitivity").font(.caption2)
                                    .padding(.top, 4)
                                Spacer()
                                Text(sensitivityLabel(for: settings.shakeAccelerationThreshold)).font(.caption2).foregroundColor(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(100000 - settings.shakeAccelerationThreshold) },
                                set: { settings.shakeAccelerationThreshold = CGFloat(100000 - $0) }
                            ), in: 10000...100000, step: 5000)
                            .onChange(of: settings.shakeAccelerationThreshold) { _ in appSettings.save() }
                        }
                    }
                    
                    if #available(macOS 13.0, *) {
                        Divider().padding(.vertical, 2)
                        
                        Toggle("Start at login", isOn: $startAtLogin)
                            .toggleStyle(.checkbox)
                            .onChange(of: startAtLogin) { _ in 
                                toggleRunAtStartup()
                            }
                            .onAppear { 
                                updateStartAtLoginState()
                            }
                            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                                updateStartAtLoginState()
                            }
                    }
                }
                .fixedSize()
            }
            
            #if !APPSTORE
            if !proLock.isPro {
                Divider().padding(.vertical, 2)
                Button(action: { page = "unlock" }) {
                    HStack {
                        Image(systemName: "heart.fill").foregroundColor(.red)
                        Text("Unlock Pro Version").fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(10)
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
            
            HStack {
                Button(action: { updater.checkForUpdates() }) {
                    HStack {
                        if updater.isChecking {
                            Image(systemName: "arrow.clockwise.circle")
                            Text("Checking...")
                        } else if updater.isDownloading {
                            ProgressView().font(.system(size: 12))
                            Text("Downloading...")
                        } else if let isUpdatable = updater.isUpdatable, let latestVersion = updater.latestVersion, isUpdatable {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Update to \(latestVersion)")
                        } else {
                            Image(systemName: "arrow.clockwise.circle")
                            Text("Check for Updates")
                        }
                    }
                }
                .disabled(updater.isChecking || updater.isDownloading)
                
                if #available(macOS 12.0, *) {
                    Button(action: { showOnboarding() }) {
                        Image(systemName: "questionmark.circle")
                        Text("Help")
                    }
                }
                
                Button(action: { NSApp.terminate(nil) }) {
                    HStack {
                        Image(systemName: "power")
                        Text("Quit")
                    }
                }
            }
            .padding(.top, 5)
        }
        .frame(minWidth: 400)
        .fixedSize()
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
                       Modifier key is mainly for performing snap resize but you can also use it to snap your windows to your zones.
                   
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
           } else if showWindowCyclingHelpDialog {
               return Alert(
                  title: Text("Window Cycling"),
                  message: Text("""
                      Window cycling allows you to quickly switch between multiple windows within the same zone.
                      
                      When you have multiple windows placed in the same zone, you can use the configured shortcuts to cycle through them.
                      
                      • Cycle Forward: Brings the next window in the zone to the front
                      • Cycle Backward: Brings the previous window in the zone to the front
                      
                      The cycling will only affect windows that are currently placed in zones, and will cycle through windows in the same zone as the currently focused window.
                      
                      Enjoy! 🥳
                  """),
                  dismissButton: .default(Text("OK"))
               )
            } else if showSnapHighlightStrategyHelpDialog {
                return Alert(
                    title: Text("Zone Highlighting Strategy"),
                    message: Text("""
                        While you are moving a window and holding Snap Key, you'll be seeing your zones; this option lets you choose how zones will be highlighted.

                        We have two options; Center Proximity and Flat:

                        • Center Proximity: The zone that has the closest center circle to mouse pointer will be highlighted.
                        • Flat: The zone visibly most front and under mouse pointer will be highlighted.

                        Note: The other option "Prioritize zone center" has higher priority.

                        Enjoy! 🥳
                    """),
                    dismissButton: .default(Text("OK"))
                )
            } else if showPerDesktopLayoutsHelpDialog {
                return Alert(
                    title: Text("Per-desktop layouts"),
                    message: Text("""
                        If you enable this option, MacsyZones will remember your preffered/selected layout for each macOS workspace (virtual desktop) / screen pair.
                    
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
                    
                        \(!proLock.isPro ? "Please buy MacsyZones to support me. 🥳": "Thank you for your support. 🥳")
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
        }
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
        }
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
                TextField("Enter License Key", text: $licenseKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.bottom, 10)
                    .onChange(of: licenseKey) { _ in
                        errorMessage = nil
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
        }
        .frame(minWidth: 300)
    }
    
    func validateLicenseKey(_ key: String) -> Bool {
        return proLock.setLicenseKey(key)
    }
    
    func unlockProVersion(with key: String) {
        debugLog("Pro version unlocked 🥳")
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
            .padding()
        }
    }
}

extension NSColor {
    func saturate(by factor: CGFloat) -> NSColor {
        guard let rgb = self.usingColorSpace(.deviceRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(s * factor, 1.0), brightness: b, alpha: a)
    }

    func enlighten(by factor: CGFloat) -> NSColor {
        guard let rgb = self.usingColorSpace(.deviceRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: s, brightness: min(b * factor, 1.0), alpha: a)
    }
}

#Preview {
    TrayPopupView(layouts: UserLayouts())
}
