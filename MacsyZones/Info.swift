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
    var onRestart: (() -> Void)?
    var onCancel: (() -> Void)?
    
    @State private var expandedImage: String? = nil
    
    var body: some View {
        ZStack {
            VStack(alignment: .center, spacing: 12) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 75, height: 75)
                
                VStack(alignment: .center, spacing: 2) {
                    Text("Accessibility Permissions Required")
                        .lineSpacing(6)
                        .font(.title)
                    
                    Spacer().frame(height: 26)
                    
                    Text("MacsyZones needs accessibility permissions to work. Please follow these steps:")
                        .font(.system(size: 13))
                        .lineSpacing(5)
                        .multilineTextAlignment(.center)
                    
                    Spacer().frame(height: 26)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("1.")
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text("Open System Settings")
                        }
                        
                        HStack {
                            Text("2.")
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text("Go to Privacy & Security → Accessibility")
                        }
                        
                        Button(action: {
                            expandedImage = "Accessibility-Permission-Tutorial-1"
                        }) {
                            Image("Accessibility-Permission-Tutorial-1")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 60)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Click to enlarge")
                        
                        HStack {
                            Text("3.")
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text("Enable MacsyZones")
                        }
                        
                        Button(action: {
                            expandedImage = "Accessibility-Permission-Tutorial-2"
                        }) {
                            Image("Accessibility-Permission-Tutorial-2")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 60)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Click to enlarge")
                    }
                    .font(.system(size: 12))
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(16)
                    
                    Spacer().frame(height: 26)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            onCancel?()
                        }) {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            onRestart?()
                        }) {
                            Text("Restart App")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer().frame(height: 26)
                    
                    Text("After enabling accessibility permissions, restart MacsyZones to continue.")
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
            
            if let imageName = expandedImage {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        expandedImage = nil
                    }
                
                VStack(alignment: .center, spacing: 0) {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 500, maxHeight: 600)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    HStack {
                        Spacer()
                        Button(action: {
                            expandedImage = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: expandedImage)
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
        
        self.level = .screenSaver
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
    
    init() {
        panel = AccessibilityPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 700))
        
        let view = AccessibilityPermissionView(
            onRestart: {
                self.dismiss()
                restartApp()
            },
            onCancel: {
                self.dismiss()
                exit(0)
            }
        )
        panel.contentView = NSHostingView(rootView: view)
        
        panel.level = .screenSaver
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
        NSApplication.shared.activate(ignoringOtherApps: true)
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
