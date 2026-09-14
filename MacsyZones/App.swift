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
var rightMouseMonitor: Any?
var shortcutMonitor: Any?

var isPreview: Bool {
    return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

@MainActor
final class WindowObserverManager {
    static let shared = WindowObserverManager()

    private struct WindowEntry {
        let element: AXUIElement
        let notifications: [CFString]
    }

    private struct AppEntry {
        let observer: AXObserver
        let appElement: AXUIElement
        var observesWindowCreation: Bool
        var shouldRetryWindowCreation: Bool
        var windows: [UInt32: WindowEntry] = [:]
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
    func observeApp(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }

        if var entry = entries[pid] {
            if entry.shouldRetryWindowCreation {
                let result = AXObserverAddNotification(entry.observer,
                                                       entry.appElement,
                                                       kAXWindowCreatedNotification as CFString,
                                                       nil)
                entry.observesWindowCreation = notificationWasRegistered(result)
                entry.shouldRetryWindowCreation = !entry.observesWindowCreation && result != .notificationUnsupported
                entries[pid] = entry
            }
            return true
        }

        let appElement = AXUIElementCreateApplication(pid)

        let observerPtr = UnsafeMutablePointer<AXObserver?>.allocate(capacity: 1)
        defer { observerPtr.deallocate() }

        guard AXObserverCreate(pid, onObserverNotification, observerPtr) == .success,
              let observer = observerPtr.pointee
        else {
            debugLog("Failed to create observer for pid \(pid)")
            return false
        }

        AXUIElementSetMessagingTimeout(appElement, 0.75)

        let createdResult = AXObserverAddNotification(observer,
                                                      appElement,
                                                      kAXWindowCreatedNotification as CFString,
                                                      nil)
        let observesWindowCreation = notificationWasRegistered(createdResult)
        if !observesWindowCreation {
            debugLog("Failed to observe window creation for pid \(pid): \(createdResult.rawValue)")
        }

        addRunLoopSource(for: observer)

        entries[pid] = AppEntry(
            observer: observer,
            appElement: appElement,
            observesWindowCreation: observesWindowCreation,
            shouldRetryWindowCreation: !observesWindowCreation && createdResult != .notificationUnsupported
        )
        debugLog("AX app observer ready: pid=\(pid), observesWindowCreation=\(observesWindowCreation)")

        return true
    }

    @discardableResult
    func observeWindow(pid: pid_t, element: AXUIElement) -> Bool {
        guard pid > 0 else { return false }

        guard isStandardWindow(element) else { return false }

        guard observeApp(pid: pid), var entry = entries[pid] else { return false }
        guard let windowID = getWindowID(from: element), windowID != 0 else {
            debugLog("Refusing to tag an AX window without a valid window ID: pid=\(pid)")
            return false
        }

        if let existing = entry.windows[windowID] {
            if CFEqual(existing.element, element) {
                return true
            }
            removeNotifications(existing.notifications,
                                observer: entry.observer,
                                element: existing.element)
            entry.windows.removeValue(forKey: windowID)
        }

        AXUIElementSetMessagingTimeout(element, 0.75)

        var registeredNotifications: [CFString] = []
        let movedNotifications: [CFString] = [
            kAXMovedNotification as CFString,
            kAXWindowMovedNotification as CFString
        ]

        for notification in movedNotifications {
            let result = AXObserverAddNotification(entry.observer, element, notification, nil)
            if notificationWasRegistered(result) {
                registeredNotifications.append(notification)
            } else {
                debugLog("AX movement registration failed: pid=\(pid), windowID=\(windowID), notification=\(notification), error=\(result.rawValue)")
            }
        }

        guard !registeredNotifications.isEmpty else {
            debugLog("Window remains retryable because no AX movement notification registered: pid=\(pid), windowID=\(windowID)")
            return false
        }

        let destroyedNotification = kAXUIElementDestroyedNotification as CFString
        let destroyedResult = AXObserverAddNotification(entry.observer,
                                                        element,
                                                        destroyedNotification,
                                                        nil)
        if notificationWasRegistered(destroyedResult) {
            registeredNotifications.append(destroyedNotification)
        } else {
            // Movement observation is still useful. A stale record is replaced
            // when the same window ID is discovered again, or removed when the
            // owning application terminates.
            debugLog("AX destruction registration unavailable: pid=\(pid), windowID=\(windowID), error=\(destroyedResult.rawValue)")
        }

        entry.windows[windowID] = WindowEntry(element: element,
                                              notifications: registeredNotifications)
        entries[pid] = entry
        debugLog("AX window observer ready: pid=\(pid), windowID=\(windowID), notifications=\(registeredNotifications.count)")
        return true
    }

    func forgetWindow(pid: pid_t, windowID: UInt32) {
        guard var entry = entries[pid] else { return }
        guard let window = entry.windows.removeValue(forKey: windowID) else { return }
        removeNotifications(window.notifications,
                            observer: entry.observer,
                            element: window.element)
        entries[pid] = entry
    }

    func forgetWindow(element: AXUIElement) {
        for (pid, var entry) in entries {
            guard let match = entry.windows.first(where: { CFEqual($0.value.element, element) }) else {
                continue
            }
            removeNotifications(match.value.notifications,
                                observer: entry.observer,
                                element: match.value.element)
            entry.windows.removeValue(forKey: match.key)
            entries[pid] = entry
            debugLog("Removed destroyed AX window: pid=\(pid), windowID=\(match.key)")
            return
        }
    }

    func removeApp(pid: pid_t) {
        guard let entry = entries.removeValue(forKey: pid) else { return }
        removeRunLoopSource(for: entry.observer)
        debugLog("Removed AX app observer: pid=\(pid)")
    }

    func refreshApplication(pid: pid_t, retry: Int = 0) {
        guard pid > 0, observeApp(pid: pid) else { return }

        // AX calls can block while a Space transition is settling. Query each
        // process away from the main thread, then update the registry on the
        // main actor so switching Spaces never freezes the overlay UI.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.75)

            var windowListRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement,
                                                       kAXWindowsAttribute as CFString,
                                                       &windowListRef)
            let windows = windowListRef as? [AXUIElement]

            Task { @MainActor [weak self] in
                guard let self else { return }

                guard result == .success, let windows else {
                    debugLog("AX window refresh failed: pid=\(pid), retry=\(retry), error=\(result.rawValue)")
                    guard retry < 3 else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 * Double(retry + 1)) { [weak self] in
                        self?.refreshApplication(pid: pid, retry: retry + 1)
                    }
                    return
                }

                for window in windows {
                    self.observeWindow(pid: pid, element: window)
                }
            }
        }
    }

    func refreshAllRunningApplications() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.processIdentifier > 0 &&
              app.processIdentifier != ownPID &&
              app.activationPolicy == .regular {
            refreshApplication(pid: app.processIdentifier)
        }
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard (roleRef as? String) == kAXWindowRole else { return false }

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        guard (subroleRef as? String) == kAXStandardWindowSubrole else { return false }

        return true
    }

    private func notificationWasRegistered(_ result: AXError) -> Bool {
        result == .success || result == .notificationAlreadyRegistered
    }

    private func removeNotifications(_ notifications: [CFString],
                                     observer: AXObserver,
                                     element: AXUIElement) {
        for notification in notifications {
            let result = AXObserverRemoveNotification(observer, element, notification)
            if result != .success && result != .notificationNotRegistered && result != .invalidUIElement {
                debugLog("Failed to remove AX notification \(notification): \(result.rawValue)")
            }
        }
    }

    private func addRunLoopSource(for observer: AXObserver) {
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopPerformBlock(observerRunLoop, CFRunLoopMode.defaultMode.rawValue) {
            CFRunLoopAddSource(self.observerRunLoop, source, .defaultMode)
        }
        CFRunLoopWakeUp(observerRunLoop)
    }

    private func removeRunLoopSource(for observer: AXObserver) {
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopPerformBlock(observerRunLoop, CFRunLoopMode.defaultMode.rawValue) {
            CFRunLoopRemoveSource(self.observerRunLoop, source, .defaultMode)
        }
        CFRunLoopWakeUp(observerRunLoop)
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
        userLayouts.load()
        checkAccessibilityPermission()
        requestAccessibilityPermissions()
        monitorActivations()
        GlobalHotkey.setup()
        
        if #available(macOS 12.0, *) {
            quickSnapper.setup()
        }
        
        Thread { [self] in
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let apps = NSWorkspace.shared.runningApplications.filter {
                $0.processIdentifier != ownPID && $0.activationPolicy == .regular
            }
            
            for app in apps {
                let pid = app.processIdentifier
                let element = AXUIElementCreateApplication(pid)

                // Observe the application even when AXWindows is temporarily
                // unavailable or empty. Otherwise its future windows can never
                // emit AXWindowCreated to MacsyZones.
                Task { @MainActor in
                    startObserving(pid: pid)
                }
                
                var windowListRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windowListRef)
                if result != .success { continue }

                if let windowList = windowListRef as? [AXUIElement]
                {
                    for window in windowList {
                        var titleValue: CFTypeRef?
                        AXUIElementCopyAttributeValue(window,
                                                      kAXTitleAttribute as CFString,
                                                      &titleValue)
                        
                        if let title = titleValue as? String, !title.isEmpty {
                            debugLog("Window is being observed: \(title)")
                        }
                        
                        Task { @MainActor in
                            startObserving(pid: pid, element: window)
                        }
                    }
                }
            }
            
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
            selector: #selector(handleAppLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

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

    @objc func handleAppLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        guard app.processIdentifier > 0,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular
        else { return }

        debugLog("Newly launched app is being observed: \(app)")
        Task { @MainActor in
            WindowObserverManager.shared.refreshApplication(pid: app.processIdentifier)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            WindowObserverManager.shared.refreshApplication(pid: app.processIdentifier)
        }
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
            Task { @MainActor in
                WindowObserverManager.shared.refreshApplication(pid: app.processIdentifier)
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
    
    func monitorShortcuts() {
        var modifierKeyTask: DispatchWorkItem?
        var prevFlags = NSEvent.ModifierFlags()
        
        shortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            DispatchQueue.main.async {
                if !macsyReady.isReady { return }

                let modifierKey = modifierFlags(for: appSettings.modifierKey) ?? .control

                modifierKeyTask?.cancel()
                modifierKeyTask = nil

                let modifierKeyUsed = !prevFlags.contains(modifierKey) && event.modifierFlags.contains(modifierKey)
                prevFlags = event.modifierFlags

                if isEditing || isQuickSnapping {
                    return
                }

                handleSnapKeyChanged(isPressed: isSnapKeyPressed(in: event.modifierFlags))

                if !snapKeyFittingActive && appSettings.modifierKey != "None" && event.type == .flagsChanged {
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
    }
    
    private func monitorRightClick() {
        rightMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { event in
            DispatchQueue.main.async {
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
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        for monitor in [mouseDownMonitor,
                        mouseDragMonitor,
                        mouseUpMonitor,
                        rightMouseMonitor,
                        shortcutMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
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
