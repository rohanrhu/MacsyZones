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

@main
struct MacsyZonesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {}
    }
}

var statusItem: NSStatusItem!
var popover: NSPopover!

var mouseUpMonitor: Any?
var mouseMoveMonitor: Any?

final class AppDelegate: NSObject, NSApplicationDelegate, Sendable {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil { return }
        
        NSApp.setActivationPolicy(.prohibited)
        
        checkIfRunning()
        
        createTrayIcon()
        setupPopover()
        
        userLayouts.load()
        requestAccessibilityPermissions()
        
        Thread { [self] in
            let apps = NSWorkspace.shared.runningApplications
            
            for app in apps {
                let pid = app.processIdentifier
                let element = AXUIElementCreateApplication(pid)
                
                var windowList: CFArray
                var windowListRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windowListRef)
                if result != .success { continue }
                windowList = windowListRef as! CFArray
                
                if result == .success,
                   let windowList = windowList as? [AXUIElement]
                {
                    Task { @MainActor in
                        startObserving(pid: pid)
                    }
                    
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
            
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                              object: nil, queue: nil) { notification in
                if let userInfo = notification.userInfo,
                   let launchedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    debugLog("Newly launched app is being observed: \(launchedApp)")
                    Task { @MainActor in
                        self.startObserving(pid: launchedApp.processIdentifier)
                    }
                }
            }
            
            Task { @MainActor in
                mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { event in
                    onMouseUp(event: event)
                }
                
                mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
                    onMouseMove(event: event)
                }
                
                spaceLayoutPreferences.startObserving()
                monitorShortcuts()
                monitorRightClick()
                
                spaceLayoutPreferences.switchToCurrent()
                
                macsyReady.isReady = true
            }
        }
        .start()
        
        appUpdater.checkForUpdates()
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
            alert.window.level = .floating
            alert.alertStyle = .informational
            alert.messageText = "MacsyZones is already running"
            alert.informativeText = "Another instance of MacsyZones is already running. This instance will exit."
            alert.addButton(withTitle: "OK")
            
            alert.window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            alert.runModal()
            
            NSApp.terminate(nil)
            return
        }
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
                button.action = #selector(togglePopover)
                button.target = self
            }

            button.action = #selector(togglePopover)
            button.target = self
        }
    }
    
    func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
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
        popover.performClose(sender)
    }

    func requestAccessibilityPermissions() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !isTrusted {
            showAccessibilityPermissionPopover()
        } else {
            debugLog("Accessibility permissions granted.")
        }
    }

    func showAccessibilityPermissionPopover() {
        let alert = NSAlert()
        alert.messageText = "MacsyZones needs accessibility permissions."
        alert.informativeText = "Restart the app after enabling it in System Settings > Privacy & Security > Accessibility. "
                              + "If you keep getting this message, close MacsyZones, open Terminal app and enter this command and try again: "
                              + "\"sudo tccutil reset All MeowingCat.MacsyZones\""
        alert.window.level = .floating
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Cancel")
        
        alert.window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            restartApp()
        } else {
            exit(0)
        }
    }
    
    func startObserving(pid: pid_t, element: AXUIElement? = nil) {
        var result: AXError
        let toObserveElement: AXUIElement
        
        if element == nil {
            toObserveElement = AXUIElementCreateApplication(pid)
        } else {
            toObserveElement = element!
        }
        
        let observerPtr: UnsafeMutablePointer<AXObserver?> = UnsafeMutablePointer<AXObserver?>.allocate(capacity: 1)
        defer { observerPtr.deallocate() }
        
        result = AXObserverCreate(pid, onObserverNotification, observerPtr)
        guard result == .success else {
            debugLog("Failed to create observer: \(result)")
            return
        }
        
        let observer = observerPtr.pointee!
         
        result = AXObserverAddNotification(observer, toObserveElement, kAXWindowMovedNotification as CFString, nil)
        guard result == .success else {
            return
        }
        
        result = AXObserverAddNotification(observer, toObserveElement, kAXUIElementDestroyedNotification as CFString, nil)
        guard result == .success else { return }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
    
    func monitorShortcuts() {
        var dispatchWorkItem: DispatchWorkItem?
        var snapKeyUsed = false
        
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            dispatchWorkItem?.cancel()
            dispatchWorkItem = nil
            
            if #available(macOS 12.0, *) {
                let quickSnapShortcut = appSettings.quickSnapShortcut.split(separator: "+")
                let requiredModifiers = Array(quickSnapShortcut.dropLast())
                let requiredKey = quickSnapShortcut.last
                
                if event.type == .keyDown {
                    if event.keyCode == 53 { // Escape key
                        quickSnapper.close()
                        return
                    }
                    if isQuickSnapShortcut(event, requiredModifiers: requiredModifiers, requiredKey: requiredKey) {
                        quickSnapper.toggle()
                        return
                    }
                    
                    // Handle cycling shortcuts
                    let cycleForwardShortcut = appSettings.cycleWindowsForwardShortcut.split(separator: "+")
                    let cycleForwardModifiers = Array(cycleForwardShortcut.dropLast())
                    let cycleForwardKey = cycleForwardShortcut.last
                    
                    let cycleBackwardShortcut = appSettings.cycleWindowsBackwardShortcut.split(separator: "+")
                    let cycleBackwardModifiers = Array(cycleBackwardShortcut.dropLast())
                    let cycleBackwardKey = cycleBackwardShortcut.last
                    
                    if isQuickSnapShortcut(event, requiredModifiers: cycleForwardModifiers, requiredKey: cycleForwardKey) {
                        cycleWindowsInZone(forward: true)
                        return
                    }
                    
                    if isQuickSnapShortcut(event, requiredModifiers: cycleBackwardModifiers, requiredKey: cycleBackwardKey) {
                        cycleWindowsInZone(forward: false)
                        return
                    }
                }
            }
            
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
                        userLayouts.currentLayoutName = layoutName
                    }
                }
                
                if event.modifierFlags.contains(snapKey) && !isFitting && isMovingAWindow {
                    snapKeyUsed = true
                    isFitting = true
                    userLayouts.currentLayout.layoutWindow.show()
                } else if isFitting {
                    isFitting = false
                    if !isQuickSnapping {
                        userLayouts.currentLayout.layoutWindow.hide()
                    }
                }
                
                if !event.modifierFlags.contains(snapKey) {
                    snapKeyUsed = false
                }
            }
            
            if !snapKeyUsed && appSettings.modifierKey != "None" {
                var modifierKey: NSEvent.ModifierFlags = .control
                
                if appSettings.modifierKey == "Command" {
                    modifierKey = .command
                } else if appSettings.modifierKey == "Option" {
                    modifierKey = .option
                }
                
                if appSettings.selectPerDesktopLayout {
                    if let layoutName = spaceLayoutPreferences.getCurrent() {
                        userLayouts.currentLayoutName = layoutName
                    }
                }
                
                let delay = Double(appSettings.modifierKeyDelay) / 1000.0
                
                if event.modifierFlags.contains(modifierKey) {
                    if !isFitting {
                        dispatchWorkItem = DispatchWorkItem {
                            if isFitting {
                                userLayouts.currentLayout.layoutWindow.show(showSnapResizers: true)
                            }
                        }
                        
                        isFitting = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: dispatchWorkItem!)
                    }
                } else {
                    dispatchWorkItem?.cancel()
                    dispatchWorkItem = nil
                    
                    if isFitting {
                        isFitting = false
                        if !isQuickSnapping {
                            userLayouts.currentLayout.layoutWindow.hide()
                        }
                    }
                }
            }
        }
    }
    
    private func monitorRightClick() {
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { event in
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
                
                userLayouts.currentLayout.layoutWindow.show()
                isFitting = true
            } else {
                userLayouts.currentLayout.layoutWindow.hide()
                isFitting = false
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let mouseUpMonitor = mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
        }
        
        if let mouseMoveMonitor = mouseMoveMonitor {
            NSEvent.removeMonitor(mouseMoveMonitor)
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
