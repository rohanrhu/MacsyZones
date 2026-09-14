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
import SwiftUI

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

class MacsyReady: ObservableObject {
    @Published var isReady: Bool = false
}

let macsyReady = MacsyReady()
let macsyProLock = ProLock()
let donationReminder = DonationReminder()
let appUpdater = AppUpdater()

@available(macOS 12.0, *)
let quickSnapper = QuickSnapper()

@available(macOS 12.0, *)
let cycleForwardHotkey = GlobalHotkey() {
    cycleWindowsInZone(forward: true)
    return noErr
}

@available(macOS 12.0, *)
let cycleBackwardHotkey = GlobalHotkey() {
    cycleWindowsInZone(forward: false)
    return noErr
}

var hasAccessibilityPermission = false
var statusItem: NSStatusItem!
var popover: NSPopover!
var accessibilityDialog: AccessibilityDialog?
var updateFailedDialog: UpdateFailedDialog?

var mouseUpMonitor: Any?
var mouseDownMonitor: Any?
var mouseDragMonitor: Any?

var isPreview: Bool {
    return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

@MainActor
final class WindowObserverManager {
    static let shared = WindowObserverManager()

    private struct AppEntry {
        let observer: AXObserver
        let appElement: AXUIElement
        var observedWindowIDs: Set<UInt32> = []
    }

    private var entries: [pid_t: AppEntry] = [:]

    private let observerRunLoop: CFRunLoop

    private final class RunLoopBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: CFRunLoop?

        func set(_ runLoop: CFRunLoop) {
            lock.lock(); value = runLoop; lock.unlock()
        }

        func get() -> CFRunLoop? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    private init() {
        let readySemaphore = DispatchSemaphore(value: 0)
        let box = RunLoopBox()

        let thread = Thread {
            let runLoop: CFRunLoop = CFRunLoopGetCurrent()
            box.set(runLoop)

            var ctx = CFRunLoopSourceContext()
            if let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &ctx) {
                CFRunLoopAddSource(runLoop, source, .commonModes)
            }

            readySemaphore.signal()

            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.25, true)
            }
        }
        thread.name = "com.macsyzones.ax-observer"
        thread.qualityOfService = QualityOfService.userInteractive
        thread.start()

        readySemaphore.wait()
        observerRunLoop = box.get()!
    }

    @discardableResult
    func observeApp(pid: pid_t, attempt: Int = 0) -> Bool {
        guard pid > 0 else { return false }

        if entries[pid] != nil { return true }

        let appElement = AXUIElementCreateApplication(pid)

        let observerPtr = UnsafeMutablePointer<AXObserver?>.allocate(capacity: 1)
        defer { observerPtr.deallocate() }

        guard AXObserverCreate(pid, onObserverNotification, observerPtr) == .success,
              let observer = observerPtr.pointee
        else {
            debugLog("Failed to create observer for pid \(pid)")
            return false
        }

        let createdStatus = AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, nil)

        guard createdStatus == .success || createdStatus == .notificationAlreadyRegistered else {
            debugLog("Failed to register window-created notification for pid \(pid), error: \(createdStatus.rawValue)")
            if attempt < 3 {
                let delayNanoseconds = UInt64(150_000_000 * (attempt + 1))
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                    self.observeApp(pid: pid, attempt: attempt + 1)
                }
            }
            return false
        }

        CFRunLoopAddSource(observerRunLoop, AXObserverGetRunLoopSource(observer), .defaultMode)

        entries[pid] = AppEntry(observer: observer, appElement: appElement)

        return true
    }

    func observeWindow(pid: pid_t, element: AXUIElement, attempt: Int = 0) {
        guard pid > 0 else { return }

        switch checkStandardWindow(element) {
        case .notStandard:
            return
        case .indeterminate:
            scheduleObserveRetry(pid: pid, element: element, attempt: attempt)
            return
        case .standard:
            break
        }

        guard observeApp(pid: pid) else {
            scheduleObserveRetry(pid: pid, element: element, attempt: attempt)
            return
        }
        guard var entry = entries[pid] else { return }

        let windowID = getWindowID(from: element)
        if let windowID, entry.observedWindowIDs.contains(windowID) { return }

        let movedStatus = AXObserverAddNotification(entry.observer, element, kAXWindowMovedNotification as CFString, nil)
        let destroyedStatus = AXObserverAddNotification(entry.observer, element, kAXUIElementDestroyedNotification as CFString, nil)

        func isRegistered(_ status: AXError) -> Bool {
            status == .success || status == .notificationAlreadyRegistered
        }

        guard isRegistered(movedStatus), isRegistered(destroyedStatus) else {
            debugLog("Failed to register AX notifications for pid \(pid) (moved=\(movedStatus.rawValue), destroyed=\(destroyedStatus.rawValue))")
            scheduleObserveRetry(pid: pid, element: element, attempt: attempt)
            return
        }

        if let windowID {
            entry.observedWindowIDs.insert(windowID)
            entries[pid] = entry
        }
    }

    private func scheduleObserveRetry(pid: pid_t, element: AXUIElement, attempt: Int) {
        guard attempt < 3 else {
            debugLog("Giving up on pid \(pid) window after repeated AX errors; it won't be observed.")
            return
        }
        let delayNanoseconds = UInt64(150_000_000 * (attempt + 1))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            self.observeWindow(pid: pid, element: element, attempt: attempt + 1)
        }
    }

    func hasObservedWindows(forPid pid: pid_t) -> Bool {
        guard let entry = entries[pid] else { return false }
        return !entry.observedWindowIDs.isEmpty
    }

    func observedWindowIDs(forPid pid: pid_t) -> Set<UInt32> {
        entries[pid]?.observedWindowIDs ?? []
    }

    func reconcile(pid: pid_t, axWindows: [AXUIElement]) {
        guard pid > 0 else { return }

        var axIDs = Set<UInt32>()
        for window in axWindows {
            if let id = getWindowID(from: window) { axIDs.insert(id) }
        }

        guard let cgList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return }

        var missing = Set<UInt32>()
        for info in cgList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowID = info[kCGWindowNumber as String] as? UInt32
            else { continue }
            if !axIDs.contains(windowID) { missing.insert(windowID) }
        }

        guard !missing.isEmpty else { return }

        debugLog("Reconcile: pid \(pid) is missing \(missing.count) window(s) from AX; hunting for them.")

        for windowID in missing {
            var element = retrieveFreshWindowElement(for: windowID)

            if element == nil {
                let title = cgList.first {
                    ($0[kCGWindowNumber as String] as? UInt32) == windowID
                }?[kCGWindowName as String] as? String

                if let title, !title.isEmpty,
                   let found = retrieveFreshWindowElementByTitle(title: title) {
                    element = found.element
                }
            }

            if let element {
                observeWindow(pid: pid, element: element)
            }
        }
    }

    func forgetWindow(pid: pid_t, windowID: UInt32) {
        guard var entry = entries[pid] else { return }
        entry.observedWindowIDs.remove(windowID)
        entries[pid] = entry
    }

    func removeApp(pid: pid_t) {
        guard let entry = entries.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(observerRunLoop, AXObserverGetRunLoopSource(entry.observer), .defaultMode)
    }

    private enum StandardWindowCheck {
        case standard
        case notStandard
        case indeterminate
    }

    private func checkStandardWindow(_ element: AXUIElement) -> StandardWindowCheck {
        var roleRef: CFTypeRef?
        let roleStatus = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard roleStatus == .success else {
            return .indeterminate
        }
        guard (roleRef as? String) == kAXWindowRole else {
            return .notStandard
        }

        var subroleRef: CFTypeRef?
        let subroleStatus = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        guard subroleStatus == .success else {
            return .indeterminate
        }
        guard (subroleRef as? String) == kAXStandardWindowSubrole else {
            return .notStandard
        }

        return .standard
    }
}

@main
struct MacsyZonesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {}
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, Sendable {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if isPreview {
            debugLog("Running in preview mode, skipping setup.")
            
            macsyReady.isReady = true
            
            return
        }
        
        NSApp.setActivationPolicy(.prohibited)
        
        checkIfRunning()
        createTrayIcon()
        setupPopover()
        checkAccessibilityPermission()
        requestAccessibilityPermissions()
        monitorActivations()
        GlobalHotkey.setup()
        
        if #available(macOS 12.0, *) {
            quickSnapper.setup()
        }
        
        Thread { [self] in
            // Register the launch-notification observer FIRST so a brand-new app launch is never
            // missed while the (potentially slow, many-processes) initial scan below is running.
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                              object: nil, queue: nil) { notification in
                guard let userInfo = notification.userInfo,
                      let launchedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }
                
                debugLog("Newly launched app is being observed: \(launchedApp)")
                let pid = launchedApp.processIdentifier

                Task { @MainActor in
                    self.startObserving(pid: pid)
                }

                self.scheduleWindowScans(forPid: pid, delays: [1.0, 3.0, 7.0])
            }
            
            // Schedule re-scans FIRST so their delays count from real launch time, not from
            // whenever the (potentially slow, many-processes) initial scan below finishes.
            scheduleWindowScans(delays: [2.0, 6.0, 12.0])
            scanAllRunningApplications()
            
            debugLog("All apps are being observed for window movement.")
            
            Task { @MainActor in
                mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
                    onMouseDown(event: event)
                }
                
                mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { event in
                    onMouseDragged(event: event)
                }
                
                mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { event in
                    onMouseUp(event: event)
                }
                
                spaceLayoutPreferences.startObserving()
                monitorShortcuts()
                monitorRightClick()
                
                spaceLayoutPreferences.switchToCurrent()
                
                macsyReady.isReady = true
                
                if #available(macOS 12.0, *) {
                   if !onboardingState.hasCompletedOnboarding && hasAccessibilityPermission {
                       showOnboarding()
                   }
                    
                    cycleForwardHotkey.register(for: appSettings.cycleWindowsForwardShortcut)
                    cycleBackwardHotkey.register(for: appSettings.cycleWindowsBackwardShortcut)
                }
            }
        }
        .start()
        
        checkUpdateState()
    }
    
    
    func checkIfRunning() {
        let notificationName = "MeowingCat.MacsyZones.CheckIfRunning"
        let uniqueNotification = Notification.Name(notificationName)
        
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        
        if isRunning {
            DistributedNotificationCenter.default().postNotificationName(
                uniqueNotification,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            
            let alert = NSAlert()
            alert.window.level = .screenSaver
            alert.window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            alert.alertStyle = .critical
            alert.messageText = "MacsyZones is already running"
            alert.informativeText = "Another instance of MacsyZones is already running. This instance will exit."
            alert.addButton(withTitle: "OK")
            
            alert.window.center()
            
            alert.window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            alert.runModal()
            
            NSApp.terminate(nil)
            return
        }
    }
    
    func checkUpdateState() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        if updateState.hasFailedUpdate(currentVersion: currentVersion) {
            showUpdateFailedDialog()
        } else {
            if let targetVersion = updateState.targetVersion {
                if currentVersion == targetVersion || isVersionGreater(currentVersion, than: targetVersion) {
                    updateState.clearUpdateAttempt()
                }
            }
            
            appUpdater.checkForUpdates()
        }
    }
    
    func showUpdateFailedDialog() {
        if updateFailedDialog == nil {
            updateFailedDialog = UpdateFailedDialog()
        }
        
        updateFailedDialog?.show()
    }
    
    func createTrayIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if let image = NSImage(named: "MenuBarIcon") {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
                image.isTemplate = true
            } else {
                button.image = NSImage(systemSymbolName: "uiwindow.split.2x1", accessibilityDescription: "MacsyZones")
                button.image?.isTemplate = true
            }
            
            button.action = #selector(togglePopover)
            button.target = self
        }
    }
    
    func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: TrayPopupView(layouts: userLayouts))
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    @objc func togglePopover(sender: AnyObject?) {
        if let button = statusItem?.button {
            if popover.isShown {
                closePopover(sender: sender)
            } else {
                showPopover(sender: button)
            }
        }
    }
    
    func showPopover(sender: NSStatusBarButton) {
        if #available(macOS 12.0, *) {
            quickSnapper.close()
        }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
    
    func closePopover(sender: AnyObject?) {
        PopoverState.shared.shouldStopListening = true
        popover.performClose(sender)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            PopoverState.shared.shouldStopListening = false
        }
    }
    
    func popoverWillClose(_ notification: Notification) {
        PopoverState.shared.shouldStopListening = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            PopoverState.shared.shouldStopListening = false
        }
    }
    
    func checkAccessibilityPermission() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func requestAccessibilityPermissions() {
        if !hasAccessibilityPermission {
            showAccessibilityPermissionPopover()
        } else {
            debugLog("Accessibility permissions granted.")
        }
    }
    
    func showAccessibilityPermissionPopover() {
        if accessibilityDialog == nil {
            accessibilityDialog = AccessibilityDialog()
        }
        accessibilityDialog?.show()
    }

    func monitorActivations() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppTermination(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc func handleAppTermination(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }

        let pid = app.processIdentifier
        Task { @MainActor in
            WindowObserverManager.shared.removeApp(pid: pid)
        }
    }

    @objc func handleAppActivation(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            let pid = app.processIdentifier
            Task { @MainActor in
                guard !WindowObserverManager.shared.hasObservedWindows(forPid: pid) else { return }
                DispatchQueue.global(qos: .utility).async {
                    self.scanWindows(forPid: pid)
                }
            }
        }

        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            let pid = app.processIdentifier
            Task { @MainActor in
                DispatchQueue.global(qos: .utility).async {
                    self.scanWindows(forPid: pid)
                }
            }
        }

        guard appSettings.selectPerDesktopLayout,
              !isQuickSnapping,
              !isEditing,
              !isFitting,
              !isSnapResizing
        else { return }

        spaceLayoutPreferences.switchToCurrent()
    }

    @objc func handleWindowDidBecomeKey(_ notification: Notification) {
        guard appSettings.selectPerDesktopLayout,
              !isQuickSnapping,
              !isEditing,
              !isFitting,
              !isSnapResizing
        else { return }
        
        spaceLayoutPreferences.switchToCurrent()
    }
    
    @MainActor
    func startObserving(pid: pid_t, element: AXUIElement? = nil) {
        if let element = element {
            WindowObserverManager.shared.observeWindow(pid: pid, element: element)
        } else {
            WindowObserverManager.shared.observeApp(pid: pid)
        }
    }
    
    func scanWindows(forPid pid: pid_t) {
        let element = AXUIElementCreateApplication(pid)

        var windowListRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windowListRef)
        guard result == .success else { return }

        let windowList = windowListRef as? [AXUIElement] ?? []

        Task { @MainActor in
            self.startObserving(pid: pid)
            WindowObserverManager.shared.reconcile(pid: pid, axWindows: windowList)
        }

        for window in windowList {
            Task { @MainActor in
                self.startObserving(pid: pid, element: window)
            }
        }
    }
    
    func scanAllRunningApplications() {
        for app in NSWorkspace.shared.runningApplications {
            scanWindows(forPid: app.processIdentifier)
        }
    }
    
    func scheduleWindowScans(forPid pid: pid_t? = nil, delays: [TimeInterval]) {
        for delay in delays {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [self] in
                if let pid {
                    scanWindows(forPid: pid)
                } else {
                    scanAllRunningApplications()
                }
            }
        }
    }
    
    func monitorShortcuts() {
        var modifierKeyTask: DispatchWorkItem?
        var snapKeyUsed = false
        var prevFlags = NSEvent.ModifierFlags()
        
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if !macsyReady.isReady { return }
            var modifierKey: NSEvent.ModifierFlags = .control
            
            if appSettings.modifierKey == "Command" {
                modifierKey = .command
            } else if appSettings.modifierKey == "Option" {
                modifierKey = .option
            }
            
            modifierKeyTask?.cancel()
            modifierKeyTask = nil
            
            let modifierKeyUsed = !prevFlags.contains(modifierKey) && event.modifierFlags.contains(modifierKey)
            prevFlags = event.modifierFlags
            
            if isEditing || isQuickSnapping {
                return
            }
            
            if appSettings.snapKey != "None" {
                var snapKey: NSEvent.ModifierFlags = .shift
                
                if appSettings.snapKey == "Control" {
                    snapKey = .control
                } else if appSettings.snapKey == "Command" {
                    snapKey = .command
                } else if appSettings.snapKey == "Option" {
                    snapKey = .option
                }
                
                if appSettings.selectPerDesktopLayout {
                    if let layoutName = spaceLayoutPreferences.getCurrent() {
                        userLayouts.setCurrentLayout(name: layoutName)
                    }
                }
                
                if event.modifierFlags.contains(snapKey) && !isFitting && isMovingAWindow {
                    snapKeyUsed = true
                    setIsFitting(true)
                    userLayouts.currentLayout.show()
                    if userLayouts.currentLayout.layoutType == .grid {
                        userLayouts.currentLayout.gridLayoutWindow?.setAnchorAtMousePosition()
                    }
                } else if isFitting && snapKeyUsed {
                    snapKeyUsed = false
                    setIsFitting(false)
                    if !isQuickSnapping {
                        userLayouts.currentLayout.hide()
                    }
                }
                
                if !event.modifierFlags.contains(snapKey) {
                    snapKeyUsed = false
                }
            }
            
            if !snapKeyUsed && appSettings.modifierKey != "None" && event.type == .flagsChanged {
                if appSettings.selectPerDesktopLayout {
                    if let layoutName = spaceLayoutPreferences.getCurrent() {
                        userLayouts.setCurrentLayout(name: layoutName)
                    }
                }
                
                let delay = Double(appSettings.modifierKeyDelay) / 1000.0
                
                if modifierKeyUsed {
                    if !isFitting {
                        modifierKeyTask = DispatchWorkItem {
                            if isFitting {
                                if userLayouts.currentLayout.layoutType == .zone {
                                    userLayouts.currentLayout.layoutWindow.show(showSnapResizers: true)
                                } else {
                                    userLayouts.currentLayout.show()
                                }
                            }
                        }
                        
                        setIsFitting(true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: modifierKeyTask!)
                    }
                } else {
                    modifierKeyTask?.cancel()
                    modifierKeyTask = nil
                    
                    if isFitting {
                        setIsFitting(false)
                        if !isQuickSnapping {
                            userLayouts.currentLayout.hide()
                        }
                    }
                }
            }
        }
    }
    
    private func monitorRightClick() {
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { event in
            if !macsyReady.isReady { return }
            if event.buttonNumber != 1 { return }
            if !appSettings.snapWithRightClick { return }
            if isEditing { return }
            if isQuickSnapping { return }
            if isSnapResizing { return }
            if !isMovingAWindow { return }
            
            if !isFitting {
                if appSettings.selectPerDesktopLayout,
                   let layoutName = spaceLayoutPreferences.getCurrent()
                {
                    userLayouts.currentLayoutName = layoutName
                }

                userLayouts.currentLayout.show()
                if userLayouts.currentLayout.layoutType == .grid {
                    userLayouts.currentLayout.gridLayoutWindow?.setAnchorAtMousePosition()
                }
                setIsFitting(true)
            } else {
                userLayouts.currentLayout.hide()
                setIsFitting(false)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let mouseUpMonitor = mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
        }
    }
}

func restartApp() {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", "sleep 1; open \"\(Bundle.main.bundlePath)\""]
    task.launch()
    
    NSApp.terminate(nil)
}
