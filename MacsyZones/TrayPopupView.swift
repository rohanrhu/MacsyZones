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
    var snapResizeThreshold: CGFloat
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
    @Published var snapResizeThreshold: CGFloat = 33.0

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
            self.snapResizeThreshold = settings.snapResizeThreshold
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
                snapResize: snapResize,
                snapResizeThreshold: snapResizeThreshold
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
    
    @ObservedObject var layouts = userLayouts
    
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
            
            Text("Options:").font(.subheadline).padding(.top, 5)
            
            HStack {
                Toggle("Enable snap resizing", isOn: $settings.snapResize)
                .onChange(of: settings.snapResize) { _ in
                    appSettings.save()
                }
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
