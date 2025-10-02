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
class KeyboardView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            window?.delegate = self
        }
        return result
    }
    
    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}

@available(macOS 12.0, *)
extension KeyboardView: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        window?.makeFirstResponder(self)
    }
}

@available(macOS 12.0, *)
struct KeyboardHandlingView: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Void
    
    func makeNSView(context: Context) -> KeyboardView {
        let view = KeyboardView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: KeyboardView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

@available(macOS 12.0, *)
struct QuickSnapperView: View {
    var windows: [QuickSnapperItem]
    
    @State private var selectedIndex: Int = 0
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
                                .background(index == selectedIndex
                                            ? Color(NSColor.selectedTextBackgroundColor).opacity(0.75)
                                            : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onHover() { isHovered in
                                    if isHovered {
                                        selectedIndex = index
                                        debugLog("Selected window: \(index)")
                                    }
                                }
                            }
                        }
                        .background(.clear)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: selectedIndex) { index in
                            scrollViewProxy.scrollTo(index, anchor: .center)
                        }
                        .onAppear() { onSelect(index: selectedIndex) }
                        .onChange(of: selectedIndex, perform: onSelect)
                    }
                }.padding().frame(height: 300)
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
        .background(BlurredWindowBackground(material: .hudWindow,
                                            blendingMode: .behindWindow)
            .cornerRadius(16).padding(.horizontal, 10))
        .overlay(KeyboardHandlingView { event in
            if [18, 19, 20, 21, 23, 22, 26, 28, 25].contains(event.keyCode) {
                let keyCodeToNumber = [18, 19, 20, 21, 23, 22, 26, 28, 25]
                let sectionNumber = keyCodeToNumber.firstIndex(of: Int(event.keyCode))! + 1
                debugLog("Quick snapping to \(sectionNumber)")
                
                let selectedWindow = windows[selectedIndex]
                
                guard let element = selectedWindow.element else { return }
                guard let windowId = selectedWindow.windowId else { return }
                
                quickSnap(sectionNumber: sectionNumber,
                          element: element,
                          windowId: windowId)
                
            } else {
                if event.keyCode == 53 { // Esc
                    quickSnapper.close()
                } else if event.keyCode == 36 { // Enter
                    quickSnapper.close()
                } else if event.keyCode == 51 { // Backspace
                    let selectedWindow = windows[selectedIndex]
                    
                    guard let element = selectedWindow.element else { return }
                    guard let windowId = selectedWindow.windowId else { return }
                    
                    if !PlacedWindows.isPlaced(windowId: windowId) {
                        return
                    }
                    
                    guard let originalSize = OriginalWindowProperties.getWindowSize(for: windowId) else { return }
                    guard let originalPosition = OriginalWindowProperties.getWindowPosition(for: windowId) else { return }
                    
                    PlacedWindows.unplace(windowId: windowId)
                    
                    resizeAndMoveWindow(element: element,
                                        newPosition: originalPosition,
                                        newSize: originalSize)
                } else if event.keyCode == 126 { // Up
                    selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
                } else if event.keyCode == 125 { // Down
                    selectedIndex = (selectedIndex + 1) % windows.count
                } else if event.keyCode == 123 { // Left
                    userLayouts.currentLayout.hideAllWindows()
                    
                    let sortedKeys = userLayouts.layouts.keys.sorted()
                    if let currentIndex = sortedKeys.firstIndex(of: userLayouts.currentLayoutName) {
                        let prevIndex = (currentIndex - 1 + sortedKeys.count) % sortedKeys.count
                        let layoutName = sortedKeys[prevIndex]
                        
                        userLayouts.currentLayoutName = layoutName
                        userLayouts.currentLayout.show()
                        
                        spaceLayoutPreferences.setCurrent(layoutName: layoutName)
                    }
                } else if event.keyCode == 124 { // Right
                    userLayouts.currentLayout.hideAllWindows()
                    
                    let sortedKeys = userLayouts.layouts.keys.sorted()
                    if let currentIndex = sortedKeys.firstIndex(of: userLayouts.currentLayoutName) {
                        let nextIndex = (currentIndex + 1) % sortedKeys.count
                        let layoutName = sortedKeys[nextIndex]
                        
                        userLayouts.currentLayoutName = layoutName
                        userLayouts.currentLayout.show()
                        
                        spaceLayoutPreferences.setCurrent(layoutName: layoutName)
                    }
                } else if event.keyCode == 48 { // Tab
                    if event.modifierFlags.contains(.shift) { // Shift+Tab
                        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
                    } else { // Tab
                        selectedIndex = (selectedIndex + 1) % windows.count
                    }
                }
            }
        }.focused($isFocused))
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
class QuickSnapper {
    var isOpen: Bool = false
    var panel: QuickSnapperPanel
    private var windows: [QuickSnapperItem] = []
    
    init() {
        panel = QuickSnapperPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 600))
        panel.contentView = NSHostingView(rootView: QuickSnapperView(windows: windows))
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.orderOut(nil)
    }
    
    func open(preload: Bool = true) {
        close()
        
        isOpen = true
        isQuickSnapping = true
        
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
    }
    
    func close() {
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
        let hostingView = NSHostingView(rootView: QuickSnapperView(windows: windows))
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
        
        setWindows(windows)
    }
}
