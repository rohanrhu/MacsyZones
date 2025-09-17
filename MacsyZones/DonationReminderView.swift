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

let INTERVALS = [5, 10, 20, 50, 5, 10, 30]

struct DonationReminderView: View {
    let donationURL: URL
    var onDismiss: (() -> Void)?
    
    init(donationURL: URL = URL(string: "https://macsyzones.com")!, onDismiss: (() -> Void)? = nil) {
        self.donationURL = donationURL
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 75, height: 75)
            
            VStack(alignment: .center, spacing: 2) {
                Text("You can buy MacsyZones to support me! 😇")
                    .lineSpacing(6)
                    .font(.title)
                
                Spacer()
                
                Text("MacsyZones is open source and free for you if you aren't comfortable with buying it. You can buy MacsyZones Pro and use without this reminder.")
                    .font(.system(size: 13))
                    .lineSpacing(5)
                
                Spacer()
                
                Button(action: {
                    NSWorkspace.shared.open(donationURL)
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
                 .cornerRadius(16)
                
                Spacer()
                
                Text("You can also visit the GitHub repository to contribute or report issues and find other ways to donate! 🤗")
                    .font(.system(size: 13))
                    .lineSpacing(4)
                
                Spacer()
                
                if #available(macOS 12.0, *) {
                    Button(action: {
                        NSWorkspace.shared.open(URL(string: "https://github.com/rohanrhu/MacsyZones")!)
                    }) {
                        Text("Visit GitHub Repository")
                            .font(.system(size: 13))
                            .padding(10)
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white.opacity(0.5))
                            }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        NSWorkspace.shared.open(URL(string: "https://github.com/rohanrhu/MacsyZones")!)
                    }) {
                        Text("Visit GitHub Repository")
                            .padding(10)
                    }
                }
                
                Spacer()
            }
            
            Spacer()
            
            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
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

class DonationReminderPanel: NSPanel {
    var selectedIndex: Binding<Int>?
    var windowsCount: Int = 0
    private var localMonitor: Any?
    
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
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.becomesKeyOnlyIfNeeded = true
    }
    
    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

class DonationReminder {
    var intervalI: Int = 0
    
    var interval: Int {
        INTERVALS[intervalI]
    }
    
    var countI = 0
    
    var panel: DonationReminderPanel
    
    init() {
        panel = DonationReminderPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 640))
        
        let view = DonationReminderView(onDismiss: { self.dismiss() })
        panel.contentView = NSHostingView(rootView: view)
        
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.center()
        panel.orderOut(nil)
    }
    
    func count() {
        if macsyProLock.isPro {
            return
        }
        
        countI += 1
        
        if countI % interval == 0 {
            // Check if zone navigation is happening and suppress donation reminder
            if isZoneNavigating {
                return
            }
                if #available(macOS 12.0, *) {
                    if isQuickSnapping {
                        self.panel.orderFront(nil)
                    // Only bring QuickSnapper to front if it's actually open
                    if quickSnapper.isOpen {
                        quickSnapper.panel.makeKeyAndOrderFront(nil)
                    } else {
                        debugLog("DonationReminder.count() - QuickSnapper is not open, not bringing it to front")
                    }
                        self.panel.makeKeyAndOrderFront(nil)
                    }
                } else {
                    self.panel.makeKeyAndOrderFront(nil)
                }
                
                self.panel.center()
            
            countI = 0
        }
    }
    
    func dismiss() {
        countI = 0
        panel.orderOut(nil)
        
        intervalI += 1
        if intervalI >= (INTERVALS.count - 1) {
            intervalI = INTERVALS.count - 1
        }
    }
}

#Preview {
    DonationReminderView()
}
