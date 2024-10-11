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

let macsyProLock = ProLock()

@main
struct MacsyZonesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {}
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    
    var mouseUpMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil { return }
        
        userLayouts.load()
        requestAccessibilityPermissions()
        
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            startObservingApp(pid: app.processIdentifier)
        }
        
        print("All apps are being observed for window movement.")
        
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                          object: nil, queue: nil) { notification in
            if let userInfo = notification.userInfo,
               let launchedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                print("Newly launched app is being observed: \(launchedApp)")
                self.startObservingApp(pid: launchedApp.processIdentifier)
            }
        }
        
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { event in
            onMouseUp(event: event)
        }
        
        spaceLayoutPreferences.startObserving()
        
        createTrayIcon()
        setupPopover()
        monitorModifierKey()
        
        NSApp.setActivationPolicy(.prohibited)
    }

    func createTrayIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "uiwindow.split.2x1", accessibilityDescription: "MacsyZones")
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
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    func closePopover(sender: AnyObject?) {
        popover.performClose(sender)
    }

    func requestAccessibilityPermissions() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !isTrusted {
            print("Requesting accessibility permissions...")
        } else {
            print("Accessibility permissions granted.")
        }
    }
    
    func startObservingApp(pid: pid_t) {
        var result: AXError
        let element = AXUIElementCreateApplication(pid)
        let observerPtr: UnsafeMutablePointer<AXObserver?> = UnsafeMutablePointer<AXObserver?>.allocate(capacity: 1)
        defer { observerPtr.deallocate() }
        
        result = AXObserverCreate(pid, onObserverNotification, observerPtr)
        guard result == .success else {
            print("Failed to create observer: \(result)")
            return
        }
        
        let observer = observerPtr.pointee!
         
        result = AXObserverAddNotification(observer, element, kAXWindowMovedNotification as CFString, nil)
        guard result == .success else {
            return
        }
        
        result = AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, nil)
        guard result == .success else { return }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
    
    func monitorModifierKey() {
        if isEditing { return }
        
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            if appSettings.modifierKey == "None" {
                return
            }
            
            var modifierKey: NSEvent.ModifierFlags = .control
            
            if appSettings.modifierKey == "Command" {
                modifierKey = .command
            } else if appSettings.modifierKey == "Option" {
                modifierKey = .option
            }
            
            if event.modifierFlags.contains(modifierKey) {
                if !isFitting {
                    isFitting = true
                    userLayouts.currentLayout.layoutWindow.show()
                }
            } else if isFitting {
                isFitting = false
                userLayouts.currentLayout.layoutWindow.hide()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let mouseUpMonitor = mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
        }
    }
}
