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

@available(macOS 12.0, *)
func isQuickSnapShortcut(_ event: NSEvent, requiredModifiers: [Substring], requiredKey: Substring?) -> Bool {
    let modifierFlags = event.modifierFlags.intersection([.command, .control, .option, .shift])
    var isMatch = true
    
    for modifier in requiredModifiers {
        switch modifier {
        case "Command":
            isMatch = isMatch && modifierFlags.contains(.command)
        case "Control":
            isMatch = isMatch && modifierFlags.contains(.control)
        case "Option":
            isMatch = isMatch && modifierFlags.contains(.option)
        case "Shift":
            isMatch = isMatch && modifierFlags.contains(.shift)
        default:
            break
        }
    }
    
    guard let requiredKey = requiredKey else { return false }
    return isMatch && (event.charactersIgnoringModifiers?.uppercased() == requiredKey.uppercased())
}

@available(macOS 12.0, *)
func quickSnap(sectionNumber: Int, element: AXUIElement, windowId: UInt32) {
    let section = userLayouts.currentLayout.layoutWindow.sectionWindows.first(where: { $0.sectionConfig.number! == sectionNumber })
    
    if let section, let sectionWindow = section.window {
        guard let (screenNumber, workspaceNumber) = SpaceLayoutPreferences.getCurrentScreenAndSpace() else { return }
        
        if !PlacedWindows.isPlaced(windowId: windowId) {
            OriginalWindowProperties.update(windowID: windowId)
        }
        
        moveWindowToMatch(element: element, targetWindow: sectionWindow)
        PlacedWindows.place(windowId: windowId,
                            screenNumber: screenNumber,
                            workspaceNumber: workspaceNumber,
                            layoutName: userLayouts.currentLayoutName,
                            sectionNumber: sectionNumber,
                            element: element)
        
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        quickSnapper.panel.makeKey()
        quickSnapper.panel.orderFront(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
            NSApp.activate(ignoringOtherApps: true)
            quickSnapper.panel.makeKey()
            quickSnapper.panel.orderFront(nil)
        }
    }
}

@available(macOS 12.0, *)
class QuickSnapperItem: Identifiable {
    var name: String
    var icon: Image
    var windowId: UInt32?
    var element: AXUIElement?
    
    var id: Int {
        return windowId?.hashValue ?? name.hashValue
    }
    
    init(name: String, icon: Image, element: AXUIElement?, windowId: UInt32?) {
        self.name = name
        self.icon = icon
        self.element = element
        self.windowId = windowId
    }
}

@available(macOS 12.0, *)
struct QuickSnapperView: View {
    @ObservedObject var model: QuickSnapper
    var windows: [QuickSnapperItem]
    
    @FocusState private var isFocused: Bool
    
    @ObservedObject var layouts = userLayouts
    
    @State private var counter: Int = 1
    
    var body: some View {
        VStack {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.secondary)
                    Text(layouts.currentLayoutName)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 16) {
                    Label {
                        Text("⟵/⟶")
                            .font(.system(size: 12, weight: .medium))
                    } icon: {
                        Image(systemName: "rectangle.split.3x3")
                            .renderingMode(.template).foregroundColor(.primary)
                    }
                    
                    Label {
                        Text("↑/↓")
                            .font(.system(size: 12, weight: .medium))
                    } icon: {
                        Image(systemName: "window.vertical.closed")
                            .renderingMode(.template).foregroundColor(.primary)
                    }
                    
                    Label {
                        Text("1-9")
                            .font(.system(size: 12, weight: .medium))
                    } icon: {
                        Image(systemName: "square.grid.3x3")
                            .renderingMode(.template).foregroundColor(.primary)
                    }
                    
                    Label {
                        Text("Backspace")
                            .font(.system(size: 12, weight: .medium))
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                            .renderingMode(.template).foregroundColor(.primary)
                    }
                }
                .padding(.vertical, 5).padding(.top, 10)
            }
            .padding(.horizontal)
            
            if windows.count == 0 {
                Text("Nothing to snap").frame(maxWidth: .infinity,
                                              minHeight: 100,
                                              alignment: .center)
            } else {
                ScrollViewReader { scrollViewProxy in
                    ScrollView {
                        VStack {
                            ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                                HStack {
                                    window.icon
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 24, height: 24)
                                        .padding(.trailing, 8)
                                    Text(window.name)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(index)
                                .padding()
                                .background(index == model.selectedIndex
                                            ? Color(NSColor.selectedTextBackgroundColor).opacity(0.75)
                                            : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 26))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .background(.clear)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: model.selectedIndex) { index in
                            scrollViewProxy.scrollTo(index, anchor: .center)
                        }
                        .onAppear() { onSelect(index: model.selectedIndex) }
                        .onChange(of: model.selectedIndex) { newIndex in
                            if isQuickSnapping {
                                onSelect(index: newIndex)
                            }
                        }
                    }
                }
                .padding()
                .frame(height: 300)
            }
            
            Button(action: {
                quickSnapper.close()
            }) {
                HStack {
                    Image(systemName: "checkmark")
                    Text("Done")
                }
            }
        }
        .padding()
        .padding(.vertical, 10)
        .background(
            BlurredWindowBackground(material: .hudWindow,
                                    blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .onDisappear {
            model.unregisterHotkeys()
        }
    }
    
    private func onSelect(index: Int) {
        if windows.count == 0 { return }
        guard let element = windows[index].element else { return }
        
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        quickSnapper.panel.makeKey()
        quickSnapper.panel.orderFront(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
            NSApp.activate(ignoringOtherApps: true)
            quickSnapper.panel.makeKey()
            quickSnapper.panel.orderFront(nil)
        }
    }
}

@available(macOS 12.0, *)
class QuickSnapperPanel: NSPanel {
    var selectedIndex: Binding<Int>?
    var windowsCount: Int = 0
    private var localMonitor: Any?
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                  styleMask: [.nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        
        self.level = .floating
        self.isMovableByWindowBackground = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isFloatingPanel = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.becomesKeyOnlyIfNeeded = true
    }
    
    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

@available(macOS 12.0, *)
class QuickSnapper: ObservableObject {
    var isOpen: Bool = false
    var panel: QuickSnapperPanel
    
    private var windows: [QuickSnapperItem] = []
    
    var toggleHotkey: GlobalHotkey?
    
    private var prevLayoutHotkey: GlobalHotkey?
    private var nextLayoutHotkey: GlobalHotkey?
    private var prevWindowHotkey: GlobalHotkey?
    private var nextWindowHotkey: GlobalHotkey?
    private var tabHotkey: GlobalHotkey?
    private var shiftTabHotkey: GlobalHotkey?
    private var unsnapHotkey: GlobalHotkey?
    private var snapZone1Hotkey: GlobalHotkey?
    private var snapZone2Hotkey: GlobalHotkey?
    private var snapZone3Hotkey: GlobalHotkey?
    private var snapZone4Hotkey: GlobalHotkey?
    private var snapZone5Hotkey: GlobalHotkey?
    private var snapZone6Hotkey: GlobalHotkey?
    private var snapZone7Hotkey: GlobalHotkey?
    private var snapZone8Hotkey: GlobalHotkey?
    private var snapZone9Hotkey: GlobalHotkey?
    private var doneHotkey: GlobalHotkey?
    private var closeHotkey: GlobalHotkey?
    
    @Published var selectedIndex = 0
    
    private var lastFocusedWindowId: UInt32?
    
    init() {
        panel = QuickSnapperPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 600))
        panel.contentView = NSHostingView(rootView: QuickSnapperView(model: self,
                                                                     windows: windows))
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.orderOut(nil)
        
        setupFocusObserver()
    }
    
    func setup() {
        setupHotkeys()
    }
    
    private func setupFocusObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil,
                                                          queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                if app.activationPolicy == .regular {
                    let pid = app.processIdentifier
                    let appElement = AXUIElementCreateApplication(pid)
                    
                    var focusedWindowRef: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
                    
                    if result == .success, let focusedWindow = focusedWindowRef {
                        let windowId = getWindowID(from: focusedWindow as! AXUIElement)
                        self?.lastFocusedWindowId = windowId
                        debugLog("Focused window ID updated: \(String(describing: windowId))")
                    }
                }
            }
        }
    }
    
    func open(preload: Bool = true) {
        close()
        
        isOpen = true
        isQuickSnapping = true
        selectedIndex = 0
        
        if preload {
            quickSnapper.loadVisibleWindows()
        }
        
        if appSettings.selectPerDesktopLayout,
           let layoutName = spaceLayoutPreferences.getCurrent()
        {
            userLayouts.currentLayoutName = layoutName
        }
        
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        
        panel.alphaValue = 0
        panel.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            panel.animator().alphaValue = 1
        }, completionHandler: {
            centerWindowOnFocusedScreen(self.panel)
            
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKey()
        })
        
        centerWindowOnFocusedScreen(panel)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
            userLayouts.currentLayout.layoutWindow.show()
        }
        
        registerHotkeys()
    }
    
    func close() {
        unregisterHotkeys()
        
        isOpen = false
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            panel.animator().alphaValue = 0
        }, completionHandler: {
            self.panel.orderOut(nil)
        })
        
        userLayouts.currentLayout.layoutWindow.hide()
        
        isQuickSnapping = false
    }
    
    func toggle() {
        if isOpen {
            close()
        } else {
            open()
        }
    }
    
    func setWindows(_ windows: [QuickSnapperItem]) {
        self.windows = windows
        let hostingView = NSHostingView(rootView: QuickSnapperView(model: self,
                                                                   windows: windows))
        panel.contentView = hostingView
    }
    
    func loadVisibleWindows() {
        var windows: [QuickSnapperItem] = []
        
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }
        
        for app in runningApps {
            let pid = app.processIdentifier as pid_t
            let element = AXUIElementCreateApplication(pid)
            
            var windowList: CFArray
            var windowListRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windowListRef)
            if result != .success { continue }
            windowList = windowListRef as! CFArray
            
            if result == .success,
               let windowList = windowList as? [AXUIElement] {
                
                for window in windowList {
                    var titleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(window,
                                                kAXTitleAttribute as CFString,
                                                &titleValue)
                    
                    if let title = titleValue as? String, !title.isEmpty {
                        let windowId = getWindowID(from: window)
                        let icon = app.icon.map { Image(nsImage: $0) } ?? Image(systemName: "app.badge")
                        
                        windows.append(QuickSnapperItem(name: title,
                                                        icon: icon,
                                                        element: window,
                                                        windowId: windowId))
                    }
                }
            }
        }
        
        if let lastWindowId = lastFocusedWindowId {
            windows.sort { item1, item2 in
                if item1.windowId == lastWindowId && item2.windowId != lastWindowId {
                    return true
                } else if item1.windowId != lastWindowId && item2.windowId == lastWindowId {
                    return false
                }
                return false
            }
        }
        
        setWindows(windows)
    }
    
    func snapToZone(_ number: Int) {
        debugLog("Quick snapping to \(number)")
        
        let selectedWindow = windows[selectedIndex]
        
        guard let element = selectedWindow.element else { return }
        guard let windowId = selectedWindow.windowId else { return }
        
        quickSnap(sectionNumber: number,
                  element: element,
                  windowId: windowId)
    }
    
    func setupHotkeys() {
        toggleHotkey = GlobalHotkey {
            Task { @MainActor in
                self.toggle()
            }
            
            return noErr
        }
        
        Task { @MainActor in
            toggleHotkey?.register(for: appSettings.quickSnapShortcut)
        }
        
        prevLayoutHotkey = GlobalHotkey {
            Task { @MainActor in
                userLayouts.currentLayout.hideAllWindows()
                
                let sortedKeys = userLayouts.layouts.keys.sorted()
                if let currentIndex = sortedKeys.firstIndex(of: userLayouts.currentLayoutName) {
                    let prevIndex = (currentIndex - 1 + sortedKeys.count) % sortedKeys.count
                    let layoutName = sortedKeys[prevIndex]
                    
                    userLayouts.currentLayoutName = layoutName
                    userLayouts.currentLayout.show()
                    
                    spaceLayoutPreferences.setCurrent(layoutName: layoutName)
                }
            }
            
            return noErr
        }
        
        nextLayoutHotkey = GlobalHotkey {
            Task { @MainActor in
                userLayouts.currentLayout.hideAllWindows()
                
                let sortedKeys = userLayouts.layouts.keys.sorted()
                if let currentIndex = sortedKeys.firstIndex(of: userLayouts.currentLayoutName) {
                    let nextIndex = (currentIndex + 1) % sortedKeys.count
                    let layoutName = sortedKeys[nextIndex]
                    
                    userLayouts.currentLayoutName = layoutName
                    userLayouts.currentLayout.show()
                    
                    spaceLayoutPreferences.setCurrent(layoutName: layoutName)
                }
            }
            
            return noErr
        }
        
        prevWindowHotkey = GlobalHotkey {
            Task { @MainActor in
                self.selectedIndex = (self.selectedIndex - 1 + self.windows.count) % self.windows.count
            }
            
            return noErr
        }
            
        nextWindowHotkey = GlobalHotkey {
            Task { @MainActor in
                self.selectedIndex = (self.selectedIndex + 1) % self.windows.count
            }
            
            return noErr
        }
        
        tabHotkey = GlobalHotkey {
            Task { @MainActor in
                self.selectedIndex = (self.selectedIndex + 1) % self.windows.count
            }
            
            return noErr
        }
        
        shiftTabHotkey = GlobalHotkey {
            Task { @MainActor in
                self.selectedIndex = (self.selectedIndex - 1 + self.windows.count) % self.windows.count
            }
            
            return noErr
        }
            
        unsnapHotkey = GlobalHotkey {
            Task { @MainActor in
                let selectedWindow = self.windows[self.selectedIndex]
                
                guard let element = selectedWindow.element else { return }
                guard let windowId = selectedWindow.windowId else { return }
                
                if !PlacedWindows.isPlaced(windowId: windowId) { return }
                
                guard let originalSize = OriginalWindowProperties.getWindowSize(for: windowId) else { return }
                guard let originalPosition = OriginalWindowProperties.getWindowPosition(for: windowId) else { return }
                
                PlacedWindows.unplace(windowId: windowId)
                
                resizeAndMoveWindow(element: element,
                                    newPosition: originalPosition,
                                    newSize: originalSize)
            }
            
            return noErr
        }
        
        snapZone1Hotkey = GlobalHotkey {
            self.snapToZone(1)
            return noErr
        }
        snapZone2Hotkey = GlobalHotkey {
            self.snapToZone(2)
            return noErr
        }
        snapZone3Hotkey = GlobalHotkey {
            self.snapToZone(3)
            return noErr
        }
        snapZone4Hotkey = GlobalHotkey {
            self.snapToZone(4)
            return noErr
        }
        snapZone5Hotkey = GlobalHotkey {
            self.snapToZone(5)
            return noErr
        }
        snapZone6Hotkey = GlobalHotkey {
            self.snapToZone(6)
            return noErr
        }
        snapZone7Hotkey = GlobalHotkey {
            self.snapToZone(7)
            return noErr
        }
        snapZone8Hotkey = GlobalHotkey {
            self.snapToZone(8)
            return noErr
        }
        snapZone9Hotkey = GlobalHotkey {
            self.snapToZone(9)
            return noErr
        }
        
        doneHotkey = GlobalHotkey {
            Task { @MainActor in
                self.close()
            }
            
            return noErr
        }
        
        closeHotkey = GlobalHotkey {
            Task { @MainActor in
                self.close()
            }
            
            return noErr
        }
    }
    
    func registerHotkeys() {
        Task { @MainActor in
            prevLayoutHotkey?.register(for: "Left")
            nextLayoutHotkey?.register(for: "Right")
            prevWindowHotkey?.register(for: "Up")
            nextWindowHotkey?.register(for: "Down")
            tabHotkey?.register(for: "Tab")
            shiftTabHotkey?.register(for: "Shift+Tab")
            unsnapHotkey?.register(for: "Backspace")
            snapZone1Hotkey?.register(for: "1")
            snapZone2Hotkey?.register(for: "2")
            snapZone3Hotkey?.register(for: "3")
            snapZone4Hotkey?.register(for: "4")
            snapZone5Hotkey?.register(for: "5")
            snapZone6Hotkey?.register(for: "6")
            snapZone7Hotkey?.register(for: "7")
            snapZone8Hotkey?.register(for: "8")
            snapZone9Hotkey?.register(for: "9")
            doneHotkey?.register(for: "Enter")
            closeHotkey?.register(for: "Escape")
        }
    }
    
    func unregisterHotkeys() {
        Task { @MainActor in
            prevLayoutHotkey?.unregister()
            nextLayoutHotkey?.unregister()
            prevWindowHotkey?.unregister()
            nextWindowHotkey?.unregister()
            tabHotkey?.unregister()
            shiftTabHotkey?.unregister()
            unsnapHotkey?.unregister()
            snapZone1Hotkey?.unregister()
            snapZone2Hotkey?.unregister()
            snapZone3Hotkey?.unregister()
            snapZone4Hotkey?.unregister()
            snapZone5Hotkey?.unregister()
            snapZone6Hotkey?.unregister()
            snapZone7Hotkey?.unregister()
            snapZone8Hotkey?.unregister()
            snapZone9Hotkey?.unregister()
            doneHotkey?.unregister()
            closeHotkey?.unregister()
        }
    }
}
