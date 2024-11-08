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
    var modifierKeyDelay: Int
    var fallbackToPreviousSize: Bool
    var onlyFallbackToPreviousSizeWithUserEvent: Bool
    var selectPerDesktopLayout: Bool
    var prioritizeCenterToSnap: Bool
    var shakeToSnap: Bool
    var shakeAccelerationThreshold: CGFloat
    var snapResize: Bool
}

class AppSettings: UserData, ObservableObject {
    @Published var modifierKey: String = "Control"
    @Published var modifierKeyDelay: Int = 500
    @Published var fallbackToPreviousSize: Bool = true
    @Published var onlyFallbackToPreviousSizeWithUserEvent: Bool = true
    @Published var selectPerDesktopLayout: Bool = true
    @Published var prioritizeCenterToSnap: Bool = true
    @Published var shakeToSnap: Bool = true
    @Published var shakeAccelerationThreshold: CGFloat = 55000.0
    @Published var snapResize: Bool = true

    init() {
        super.init(name: "AppSettings", data: "{}", fileName: "AppSettings.json")
    }

    override func load() {
        super.load()

        let jsonData = data.data(using: .utf8)!
        
        do {
            let settings = try JSONDecoder().decode(AppSettingsData.self, from: jsonData)
            
            self.modifierKey = settings.modifierKey
            self.modifierKeyDelay = settings.modifierKeyDelay
            self.fallbackToPreviousSize = settings.fallbackToPreviousSize
            self.onlyFallbackToPreviousSizeWithUserEvent = settings.onlyFallbackToPreviousSizeWithUserEvent
            self.selectPerDesktopLayout = settings.selectPerDesktopLayout
            self.prioritizeCenterToSnap = settings.prioritizeCenterToSnap
            self.shakeToSnap = settings.shakeToSnap
            self.shakeAccelerationThreshold = settings.shakeAccelerationThreshold
            self.snapResize = settings.snapResize
        } catch {
            print("Error parsing settings JSON: \(error)")
        }
    }

    override func save() {
        do {
            let settings = AppSettingsData(
                modifierKey: modifierKey,
                modifierKeyDelay: modifierKeyDelay,
                fallbackToPreviousSize: fallbackToPreviousSize,
                onlyFallbackToPreviousSizeWithUserEvent: onlyFallbackToPreviousSizeWithUserEvent,
                selectPerDesktopLayout: selectPerDesktopLayout,
                prioritizeCenterToSnap: prioritizeCenterToSnap,
                shakeToSnap: shakeToSnap,
                shakeAccelerationThreshold: shakeAccelerationThreshold,
                snapResize: snapResize
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

struct Main: View {
    @State var proLock: ProLock
    
    @Binding var page: String
    
    @ObservedObject var settings = appSettings
    
    @Binding var layouts: UserLayouts
    @Binding var selectedLayout: String
    
    @State var showNotProDialog: Bool = false
    @State var showAboutDialog: Bool = false
    
    @State private var startAtLogin = false
    
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
                    showAboutDialog = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.bottom, 10)

            Text("Layouts:").font(.subheadline)
            
            if #available(macOS 14.0, *) {
                Picker("Select Layout", selection: $selectedLayout) {
                    ForEach(Array(layouts.layouts.keys), id: \.self) { name in
                        Text(name)
                    }
                }.onAppear {
                    if let preferedLayout = spaceLayoutPreferences.getCurrent() {
                        selectedLayout = preferedLayout
                        userLayouts.currentLayoutName = selectedLayout
                    }
                }.onChange(of: selectedLayout) {
                    let wasEditing = isEditing
                    stopEditing()
                    userLayouts.selectLayout(selectedLayout)
                    if wasEditing {
                        startEditing()
                    }
                    
                    spaceLayoutPreferences.setCurrent(layoutName: selectedLayout)
                    spaceLayoutPreferences.save()
                }.labelsHidden()
                    .pickerStyle(MenuPickerStyle())
                    .padding(.bottom, 10)
            } else {
                Picker("Select Layout", selection: $selectedLayout) {
                    ForEach(Array(layouts.layouts.keys), id: \.self) { name in
                        Text(name)
                    }
                }.onAppear {
                    if let preferedLayout = spaceLayoutPreferences.getCurrent() {
                        selectedLayout = preferedLayout
                        userLayouts.currentLayoutName = selectedLayout
                    }
                }.labelsHidden()
                 .pickerStyle(MenuPickerStyle())
                 .padding(.bottom, 10)
                 .onChange(of: selectedLayout) { _ in
                     let wasEditing = isEditing
                     stopEditing()
                     userLayouts.selectLayout(selectedLayout)
                     if wasEditing {
                         startEditing()
                     }
                 
                     spaceLayoutPreferences.setCurrent(layoutName: selectedLayout)
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
                    if layouts.layouts.count < 2 { return }
                    
                    stopEditing()
                    
                    let firstLayout = layouts.layouts.first!.value
                    let toRemoveLayoutName = selectedLayout
                    let toRemoveLayout = layouts.layouts[toRemoveLayoutName]
                    
                    layouts.layouts.removeValue(forKey: toRemoveLayoutName)
                    layouts.currentLayoutName = firstLayout.name
                    selectedLayout = firstLayout.name
                    
                    userLayouts.save()
                    
                    toRemoveLayout?.layoutWindow.closeAllWindows()
                }) {
                    HStack {
                        Image(systemName: "trash")
                    }
                }.disabled(layouts.layouts.count < 2)
            }.padding(.bottom, 5)

            Divider()

            Text("Modifier Key:")
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
            
            Text("Delay: \(String(format: "%.2f", Double(settings.modifierKeyDelay) / 1000.0)) secs")
                .font(.subheadline)
                .padding(.top, 5)
            Slider(value: Binding(
                get: { Double(settings.modifierKeyDelay) },
                set: { settings.modifierKeyDelay = Int($0) }
            ), in: 0...2000, step: 100)
            .frame(alignment: .center)
            .padding(.bottom, 10)
            .onChange(of: settings.modifierKeyDelay) { _ in
                appSettings.save()
            }
            
            Text("Options:").font(.subheadline)
            
            HStack {
                Toggle("Enable snap resizing", isOn: $settings.snapResize)
                .onChange(of: settings.snapResize) { _ in
                    appSettings.save()
                }
                Spacer()
            }.padding(.bottom, 5)
            
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
                    Text("Shake Sensitivity").font(.subheadline)
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
            
            if #available(macOS 13.0, *) {
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
            
            Divider()

            Button("Quit MacsyZones") {
                NSApp.terminate(nil)
            }
        }.padding()
         .frame(width: 240)
         .alert(isPresented: $showAboutDialog) {
             let licenseInfo = proLock.isPro ? "\nLicensed for: \(proLock.owner ?? "Unknown User")" : "(Free version)"
             
             return Alert(
                 title: Text("About MacsyZones"),
                 message: Text("""
                     Copyright ©️ 2024, Oğuzhan Eroğlu (https://meowingcat.io).
                     
                     MacsyZones helps you organize your windows efficiently on macOS. Finally it is here with you 🥳
                     
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

struct NewView: View {
    @Binding var page: String
    @Binding var layouts: UserLayouts
    @Binding var selectedLayout: String

    @State var layoutName: String = "My Layout"
    
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
                        let newLayout = UserLayout(name: layoutName, sectionConfigs: [SectionConfig.defaultSection])
                        layouts.layouts[layoutName] = newLayout
                        
                        selectedLayout = layoutName
                        layouts.currentLayoutName = layoutName
                        
                        userLayouts.save()
                        
                        startEditing()
                        
                        page = "main"
                    }) {
                        Image(systemName: "checkmark").foregroundColor(.green)
                        Text("Create")
                    }
                }
            }
        }.padding()
    }
}

struct RenameView: View {
    @Binding var page: String
    @Binding var layouts: UserLayouts
    @Binding var selectedLayout: String
    
    @State var layoutName: String
    
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
                        if let layout = layouts.layouts[selectedLayout] {
                            layouts.layouts.removeValue(forKey: selectedLayout)
                            layouts.layouts[layoutName] = layout
                            selectedLayout = layoutName
                            
                            layouts.layouts[layoutName]?.name = layoutName
                            layouts.layouts[layoutName]?.layoutWindow.name = layoutName
                            
                            layouts.currentLayoutName = layoutName
                            
                            userLayouts.save()
                        }
                        
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
    @State var layouts: UserLayouts
    @ObservedObject var selectedLayout = actualSelectedLayout
    
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
                    NewView(page: $page, layouts: $layouts, selectedLayout: $selectedLayout.selectedLayout)
                case "rename":
                    RenameView(page: $page, layouts: $layouts, selectedLayout: $selectedLayout.selectedLayout, layoutName: selectedLayout.selectedLayout)
                case "unlock":
                    UnlockProView(proLock: proLock, page: $page)
                default:
                    Main(proLock: proLock, page: $page, layouts: $layouts, selectedLayout: $selectedLayout.selectedLayout)
                }
            }
        }
    }
}

#Preview {
    TrayPopupView(layouts: UserLayouts(), selectedLayout: actualSelectedLayout)
}
