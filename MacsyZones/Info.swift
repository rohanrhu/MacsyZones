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

struct AccessibilityPermissionView: View {
    var onOpenSettings: (() -> Void)?
    var onRecheck: (() -> Void)?
    var onRestart: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 75, height: 75)

            VStack(alignment: .center, spacing: 2) {
                Text("Window Control Permission Required")
                    .lineSpacing(6)
                    .font(.title)

                Spacer().frame(height: 20)

                Text("MacsyZones needs permission to arrange the windows of other apps. Follow these steps:")
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 20)

                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Open System Settings.")
                    step(2, "Go to Privacy & Security → System & App Protection Override.")
                    step(3, "Add MacsyZones to the list and switch it on.")
                    step(4, "Come back here and click “Check Again”. No restart is needed.")
                }
                .font(.system(size: 12.5))
                .multilineTextAlignment(.leading)
                .padding(14)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(16)

                Spacer().frame(height: 16)

                Text("On macOS 27.0–27.2 this pane is called “Device Control and Data Access”; on earlier versions the permission lives under “Accessibility”. MacsyZones is not listed in the Accessibility pane, which is expected: that pane only lists apps with an accessibility designation.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 20)

                VStack(spacing: 10) {
                    Button {
                        onOpenSettings?()
                    } label: {
                        Text("Open System Settings")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Button {
                            onRecheck?()
                        } label: {
                            Text("Check Again")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(9)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onRestart?()
                        } label: {
                            Text("Restart App")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(9)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onQuit?()
                    } label: {
                        Text("Quit MacsyZones")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                }

            }
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 20)
        .background(BlurredWindowBackground(material: .hudWindow,
                                            blendingMode: .behindWindow)
            .cornerRadius(16).padding(.horizontal, 10))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .frame(width: 440)
        .multilineTextAlignment(.center)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number).")
                .fontWeight(.bold)
                .foregroundColor(.blue)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

class AccessibilityPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                  styleMask: [.fullSizeContentView, .hudWindow, .nonactivatingPanel],
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
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.becomesKeyOnlyIfNeeded = true
    }
}

class AccessibilityDialog {
    private var panel: AccessibilityPanel

    init(onOpenSettings: (() -> Void)? = nil,
         onRecheck: (() -> Void)? = nil,
         onRestart: (() -> Void)? = nil) {
        panel = AccessibilityPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 600))

        let view = AccessibilityPermissionView(
            onOpenSettings: onOpenSettings,
            onRecheck: onRecheck,
            onRestart: {
                self.dismiss()
                restartApp()
            },
            onQuit: {
                self.dismiss()
                NSApplication.shared.terminate(nil)
            }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 460, height: 620)
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: 460, height: 620))

        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        positionInLeftHalf()
        panel.orderOut(nil)
    }

    private func positionInLeftHalf() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame

        let leftHalfCenterX = screenFrame.origin.x + (screenFrame.width / 4)
        let centerY = screenFrame.origin.y + (screenFrame.height - panelFrame.height) / 2

        panel.setFrameOrigin(NSPoint(x: leftHalfCenterX - panelFrame.width / 2, y: centerY))
    }

    func show() {
        panel.orderFrontRegardless()
        positionInLeftHalf()
    }

    func dismiss() {
        panel.orderOut(nil)
    }
}

struct UpdateFailedView: View {
    var onDismiss: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 75, height: 75)
            
            VStack(alignment: .center, spacing: 2) {
                Text("Update Failed")
                    .lineSpacing(6)
                    .font(.title)
                    .foregroundColor(.orange)
                
                Spacer().frame(height: 26)
                
                Text("Auto-update was unsuccessful.")
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                
                Spacer().frame(height: 20)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Please download and install the latest version manually.")
                            .font(.system(size: 12))
                    }
                    
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Text("Visit our website to get the latest version.")
                            .font(.system(size: 12))
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(16)
                
                Spacer().frame(height: 26)
                
                VStack(spacing: 8) {
                    Button(action: {
                        if let url = URL(string: "https://macsyzones.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "safari")
                            Text("Download Latest Version")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        onDismiss?()
                    }) {
                        Text("Continue with Current Version")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer().frame(height: 20)
                
                Text("You can continue using the current version of MacsyZones.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 20)
        .background(BlurredWindowBackground(material: .hudWindow,
                                            blendingMode: .behindWindow)
            .cornerRadius(16).padding(.horizontal, 10))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }
}

class UpdateFailedDialog {
    private var panel: AccessibilityPanel
    
    init() {
        panel = AccessibilityPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 450))
        
        let view = UpdateFailedView(
            onDismiss: {
                self.dismiss()
            }
        )
        panel.contentView = NSHostingView(rootView: view)
        
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        positionCenter()
        panel.orderOut(nil)
    }
    
    private func positionCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        
        let centerX = screenFrame.origin.x + (screenFrame.width - panelFrame.width) / 2
        let centerY = screenFrame.origin.y + (screenFrame.height - panelFrame.height) / 2
        
        panel.setFrameOrigin(NSPoint(x: centerX, y: centerY))
    }
    
    func show() {
        panel.orderFrontRegardless()
        positionCenter()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    func dismiss() {
        panel.orderOut(nil)
    }
}

#Preview("Accessibility Permission") {
    AccessibilityPermissionView()
        .frame(width: 420, height: 700)
}

#Preview("Update Failed") {
    UpdateFailedView()
        .frame(width: 420, height: 450)
}
