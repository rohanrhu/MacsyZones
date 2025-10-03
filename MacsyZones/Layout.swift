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

import Cocoa
import SwiftUI
import AppKit

struct SectionView: View {
    @ObservedObject var sectionWindow: SectionWindow
    
    var backgroundColor: Color {
        sectionWindow.isHovered ? Color.accentColor.opacity(0.1) : Color.white.opacity(0.1)
    }
    
    var borderColor: Color {
        sectionWindow.isHovered ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.9)
    }
    
    var centerCircleBckground: AnyView {
        if hasLiquidGlass {
            return AnyView(
                LiquidGlassView(variant: .v11, cornerRadius: .infinity) {}
                    .background(Circle().stroke((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.6 : 0.1), lineWidth: 4))
            )
        } else {
            if #available(macOS 14.0, *) {
                return hasLiquidGlass ? AnyView(Circle()
                        .fill((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.25 : 0.05))
                        .stroke((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.6 : 0.1), lineWidth: 4))
                    : AnyView(Circle()
                        .fill((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.2 : 0.1))
                        .stroke((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.5 : 0.25), lineWidth: 4)
                        .shadow(color: (sectionWindow.isHovered ? Color.accentColor : Color.black).opacity(sectionWindow.isHovered ? 0.5 : 0.5), radius: 2, x: 0, y: 0))
            } else {
                return AnyView(
                    Circle()
                        .fill((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.1 : 0.05))
                )
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Group {
                    Text(String(sectionWindow.number))
                        .frame(width: 100, height: 100)
                        .font(.system(size: 50))
                        .foregroundColor((sectionWindow.isHovered ? Color.accentColor: Color.white).opacity(0.5))
                        .blendMode(.difference)
                }
                .fixedSize()
                .shadow(color: (sectionWindow.isHovered ? Color.accentColor: Color.black), radius: 8, x: 0, y: 0)
                .background(centerCircleBckground)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .modifier {
                if #available(macOS 14.0, *) {
                    $0
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .fill(backgroundColor)
                                .stroke(borderColor, lineWidth: 5)
                        )
                        .cornerRadius(26)
                } else {
                    $0
                        .background(BlurredSectionBackground(opacity: sectionWindow.isHovered ? 0.5 : 0.35))
                        .border(borderColor, width: 5)
                        .cornerRadius(26)
                }
            }
        }
    }
}

class EditorSectionView: NSView {
    private let edgeSize: CGFloat = 2
    
    var onDelete: (() -> Void)?
    
    var number: Int = 0 {
        didSet {
            label.stringValue = String(number)
        }
    }
    
    private let background = NSView()
    
    private let label = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")

    private let circleView = NSView()
    private let deleteButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        background.frame = bounds
        background.wantsLayer = true
        background.layer = CALayer()
        background.layer?.cornerRadius = 26
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 3
        background.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        background.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
        background.autoresizingMask = [.width, .height]
        addSubview(background, positioned: .below, relativeTo: nil)
        
        label.font = NSFont.systemFont(ofSize: 50, weight: .light)
        label.textColor = NSColor.controlAccentColor
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.shadow = NSShadow()
        label.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.4)
        label.shadow?.shadowOffset = NSSize(width: 0, height: -1)
        label.shadow?.shadowBlurRadius = 2
        addSubview(label)
        
        sizeLabel.font = NSFont.systemFont(ofSize: 20, weight: .light)
        sizeLabel.textColor = NSColor.controlAccentColor.withAlphaComponent(0.85)
        sizeLabel.alignment = .center
        sizeLabel.isEditable = false
        sizeLabel.isSelectable = false
        sizeLabel.isBezeled = false
        sizeLabel.backgroundColor = .clear
        sizeLabel.drawsBackground = false
        sizeLabel.shadow = NSShadow()
        sizeLabel.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.4)
        sizeLabel.shadow?.shadowOffset = NSSize(width: 0, height: -1)
        sizeLabel.shadow?.shadowBlurRadius = 2
        addSubview(sizeLabel)

        circleView.wantsLayer = true
        circleView.layer = CALayer()
        circleView.layer?.cornerRadius = 75
        circleView.layer?.masksToBounds = true
        circleView.layer?.backgroundColor = (
            NSColor.controlAccentColor.withAlphaComponent(0.2).blended(withFraction: 0.5, of: .white) ??
            NSColor.controlAccentColor.withAlphaComponent(0.05)
        ).cgColor
        circleView.layer?.borderColor = (
            NSColor.controlAccentColor.withAlphaComponent(0.25).blended(withFraction: 0.5, of: .white) ??
            NSColor.controlAccentColor.withAlphaComponent(0.1)
        ).cgColor
        circleView.layer?.borderWidth = 2
        addSubview(circleView)
        
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")?.withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        deleteButton.frame.size = CGSize(width: 80, height: 80)
        deleteButton.imagePosition = .imageOnly
        deleteButton.contentTintColor = .white
        deleteButton.isBordered = false
        deleteButton.wantsLayer = true
        deleteButton.layer?.backgroundColor = NSColor.controlAccentColor.saturate(by: 1.5).cgColor
        deleteButton.layer?.cornerRadius = 8
        deleteButton.layer?.masksToBounds = true
        deleteButton.target = self
        deleteButton.action = #selector(deleteSection)
        addSubview(deleteButton)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        circleView.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            circleView.widthAnchor.constraint(equalToConstant: 150),
            circleView.heightAnchor.constraint(equalTo: circleView.widthAnchor),
            
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            sizeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            sizeLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 110),
            
            deleteButton.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
        ])
        
        circleView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
        circleView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(1).cgColor
        
        deleteButton.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        
        let cursorInBg = CFStringCreateWithCString(kCFAllocatorDefault, "SetsCursorInBackground", 0)
        CGSSetConnectionProperty(_CGSDefaultConnection(), _CGSDefaultConnection(), cursorInBg, kCFBooleanTrue)
    }
    
    override func layout() {
        super.layout()
        sizeLabel.stringValue = "\(Int(bounds.width))x\(Int(bounds.height))"
    }
    
    @objc private func deleteSection() {
        onDelete?()
    }
}

struct BlurredWindowBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct BlurredSectionBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var opacity: CGFloat = 0.35
    
    init(opacity: CGFloat = 0.35) {
        material = .hudWindow
        blendingMode = .behindWindow
        self.opacity = opacity
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 7
        visualEffectView.layer?.opacity = Float(opacity)
        visualEffectView.layer?.borderWidth = 5
        visualEffectView.layer?.backgroundColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.7).cgColor
        visualEffectView.layer?.borderColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(1).cgColor
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.layer?.opacity = Float(opacity)
        nsView.layer?.backgroundColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.7).cgColor
    }
}

struct ScreenChangeWarningView: View {
    var onDismiss: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "display.2")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .center, spacing: 2) {
                Text("Layout Design")
                    .lineSpacing(6)
                    .font(.title2)
                
                Spacer().frame(height: 16)
                
                Text("A layout can be designed on one screen.")
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer().frame(height: 8)
                
                Text("You can select your preferred layouts for each screen and workspace.")
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer().frame(height: 20)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Tip: Design different layouts for each screen and workspace for your workflow.")
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(12)
                
                Spacer().frame(height: 20)
                
                Button(action: {
                    onDismiss?()
                }) {
                    Text("Got It")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
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

class ScreenChangeWarningPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                  styleMask: [.fullSizeContentView, .hudWindow, .nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        
        self.level = .statusBar + 1
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

class ScreenChangeWarningDialog {
    private var panel: ScreenChangeWarningPanel
    var onDismiss: (() -> Void)?
    
    init() {
        panel = ScreenChangeWarningPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 340))
        
        let view = ScreenChangeWarningView(
            onDismiss: {
                self.dismiss()
            }
        )
        panel.contentView = NSHostingView(rootView: view)
        
        panel.level = .statusBar + 1
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.orderOut(nil)
    }
    
    private func positionOnScreen(_ screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        
        let centerX = screenFrame.origin.x + (screenFrame.width - panelFrame.width) / 2
        let centerY = screenFrame.origin.y + (screenFrame.height - panelFrame.height) / 2
        
        panel.setFrameOrigin(NSPoint(x: centerX, y: centerY))
    }
    
    func show(on screen: NSScreen?) {
        if let screen = screen {
            positionOnScreen(screen)
        } else {
            panel.center()
        }
        panel.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    
    func dismiss() {
        panel.orderOut(nil)
        onDismiss?()
    }
}

class EditorSectionWindowDelegate: NSObject, NSWindowDelegate {
    weak var sectionWindow: SectionWindow?
    var originalScreen: NSScreen?
    var hasShownWarning = false
    var warningDialog: ScreenChangeWarningDialog?
    
    init(sectionWindow: SectionWindow?) {
        self.sectionWindow = sectionWindow
        self.originalScreen = sectionWindow?.editorWindow.screen
        super.init()
        self.warningDialog = ScreenChangeWarningDialog()
        self.warningDialog?.onDismiss = { [weak self] in
            self?.hasShownWarning = false
        }
    }
    
    func showScreenChangeWarning() {
        warningDialog?.show(on: originalScreen)
    }
    
    func windowDidChangeScreen(_ notification: Notification) {
        guard isEditing else { return }
        guard let window = notification.object as? NSWindow else { return }
        guard let currentScreen = window.screen else { return }
        guard let originalScreen = originalScreen else { return }
        
        if currentScreen != originalScreen {
            debugLog("EditorSectionWindow moved to another screen, bringing it back")
            
            if !hasShownWarning {
                hasShownWarning = true
                showScreenChangeWarning()
            }
            
            let currentFrame = window.frame
            let relativeX = currentFrame.origin.x - currentScreen.frame.origin.x
            let relativeY = currentFrame.origin.y - currentScreen.frame.origin.y
            
            let newX = originalScreen.frame.origin.x + relativeX
            let newY = originalScreen.frame.origin.y + relativeY
            
            window.setFrameOrigin(NSPoint(x: newX, y: newY))
        }
    }
}

class EditorSectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var areCursorRectsEnabled: Bool { true }
}

class SectionWindow: Hashable, ObservableObject {
    @Published var number: Int = 0 {
        didSet {
            guard let editorWindow else { return }
            guard let editorSectionView = editorWindow.contentView as? EditorSectionView else { return }
            
            editorSectionView.number = number
        }
    }
    @Published var isHovered: Bool = false
    var editorWindow: NSWindow!
    var layoutWindow: LayoutWindow!
    var window: NSWindow!
    var sectionConfig: SectionConfig
    var editorWindowDelegate: EditorSectionWindowDelegate?
    
    var isEditing: Bool { layoutWindow.isEditing }
    
    let onDelete: ((SectionWindow) -> Void)

    init(number: Int, layoutWindow: LayoutWindow, sectionConfig: SectionConfig, onDelete: @escaping ((SectionWindow) -> Void)) {
        self.number = number
        self.sectionConfig = sectionConfig
        self.layoutWindow = layoutWindow
        self.onDelete = onDelete
        
        let contentRect = sectionConfig.getRect()

        window = NSWindow(contentRect: contentRect,
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.title = "Macsy Section"
        window.contentView = NSHostingView(rootView: SectionView(sectionWindow: self))
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar - 2

        layoutWindow.window.addChildWindow(window, ordered: .above)
        
        editorWindow = EditorSectionWindow(contentRect: contentRect,
                                           styleMask: [.resizable, .fullSizeContentView, .titled, .unifiedTitleAndToolbar],
                                           backing: .buffered,
                                           defer: false)
        editorWindow.title = ""
        editorWindow.isOpaque = true
        editorWindow.backgroundColor = .clear
        editorWindow.titlebarAppearsTransparent = true
        editorWindow.isMovableByWindowBackground = true
        editorWindow.level = .statusBar - 1
        editorWindow.hasShadow = true
        editorWindow.acceptsMouseMovedEvents = true
        
        editorWindow.contentView?.wantsLayer = true
        editorWindow.contentView?.layer?.cornerRadius = 7
        
        editorWindow.standardWindowButton(.closeButton)?.isEnabled = false
        editorWindow.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        editorWindow.standardWindowButton(.zoomButton)?.isEnabled = true
        
        editorWindow.standardWindowButton(.closeButton)?.isHidden = false
        editorWindow.standardWindowButton(.miniaturizeButton)?.isHidden = false
        editorWindow.standardWindowButton(.zoomButton)?.isHidden = false
        
        let editorSectionView = EditorSectionView(frame: NSRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height))
        editorSectionView.onDelete = { [unowned self] in
            onDelete(self)
        }
        editorSectionView.number = number
        editorWindow.contentView = editorSectionView
        
        editorWindowDelegate = EditorSectionWindowDelegate(sectionWindow: self)
        editorWindow.delegate = editorWindowDelegate
        
        layoutWindow.window.addChildWindow(editorWindow, ordered: .above)
        
        window.orderOut(nil)
        editorWindow.orderOut(nil)
    }
    
    func reset(sectionConfig: SectionConfig) {
        number = sectionConfig.number!
        self.sectionConfig = sectionConfig
        
        let contentRect = sectionConfig.getRect()
        window.setFrame(contentRect, display: true, animate: false)
        editorWindow.setFrame(contentRect, display: true, animate: false)
        
        editorWindowDelegate?.originalScreen = editorWindow.screen
    }
    
    func getBounds() -> SectionBounds {
        let screenSize = NSScreen.main!.frame
        
        return SectionBounds(
            widthPercentage: window.frame.width / screenSize.width,
            heightPercentage: window.frame.height / screenSize.height,
            xPercentage: window.frame.minX / screenSize.width,
            yPercentage: window.frame.minY / screenSize.height
        )
    }
    
    func startEditing() {
        editorWindowDelegate?.originalScreen = editorWindow.screen
        editorWindow.orderFront(nil)
        editorWindow.level = .statusBar - 1
        window.orderOut(nil)
    }
    
    func stopEditing() {
        editorWindow.orderOut(nil)
    }
    
    static func == (lhs: SectionWindow, rhs: SectionWindow) -> Bool {
        lhs.number == rhs.number
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(number)
    }
}

struct EditorBarView: View {
    var layoutWindow: LayoutWindow
    
    var onNewSection: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void
    
    @State var showNotProDialog = false
    
    var body: some View {
        HStack {
            Spacer()
            if #available(macOS 14.0, *) {
                Button(action: {
                    onNewSection()
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Section")
                    }
                }.frame(maxHeight: .infinity)
                 .buttonStyle(AccessoryBarButtonStyle())
            } else {
                Button(action: {
                    onNewSection()
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Section")
                    }
                }.frame(maxHeight: .infinity)
            }
            Divider()
            if #available(macOS 14.0, *) {
                Button(action: onSave) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Save")
                    }
                }.frame(maxHeight: .infinity)
                 .buttonStyle(AccessoryBarButtonStyle())
            } else {
                Button(action: onSave) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Save")
                    }
                }.frame(maxHeight: .infinity)
            }
            Divider()
            if #available(macOS 14.0, *) {
                Button(action: onCancel) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                }.frame(maxHeight: .infinity)
                 .buttonStyle(AccessoryBarButtonStyle())
            } else {
                Button(action: onCancel) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                }.frame(maxHeight: .infinity)
            }
            Spacer()
        }
        .frame(height: 50)
        .fixedSize(horizontal: false, vertical: true)
        .background(BlurredWindowBackground(material: .hudWindow, blendingMode: .behindWindow).cornerRadius(26).padding(.horizontal, 7))
        .alert(isPresented: $showNotProDialog) {
            Alert(
                title: Text("Omg! 😊"),
                message: Text("You must buy MacsyZones Pro to unlock this feature."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

struct LayoutView: View {
    var sections: [SectionView]

    var body: some View {
        ZStack {
            ForEach(0..<sections.count, id: \.self) { index in
                sections[index]
            }
        }
    }
}

func macssyStartEditing() { startEditing() }
func macsyStopEditing() { stopEditing() }

class LayoutWindow {
    var name: String
    var sectionConfigs: [Int:SectionConfig] = [:]
    
    var window: NSWindow
    var sectionWindows: [SectionWindow] = []
    var editorBarWindow: NSWindow
    
    var isEditing: Bool = false
    
    var unsavedNewSectionWindows: [SectionWindow] = []
    var unsavedNewSectionConfigs: [Int:SectionConfig] = [:]
    var unsavedRemovedSectionWindows: [SectionWindow] = []
    
    var sectionResizers: [SnapResizer] = []
    
    var mouseMonitor: Any?
    var snapResizerProximityThreshold: CGFloat { appSettings.snapResizeThreshold }
    
    var activeSnapResizers: [String: SnapResizer] = [:]

    var nextNumber: Int {
        if unsavedNewSectionConfigs.count > 0 {
            return (unsavedNewSectionConfigs.values.compactMap { $0.number ?? 0 }.max() ?? 0) + 1
        }
        return (sectionConfigs.values.compactMap { $0.number ?? 0 }.max() ?? 0) + 1
    }
    
    var isShown = false

    init(name: String, sectionConfigs: [SectionConfig]) {
        self.name = name
        
        let focusedScreen = getFocusedScreen()
        let screenSize = focusedScreen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)

        window = NSWindow(contentRect: screenSize,
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.title = "Macsy Layout"
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.isMovableByWindowBackground = false
        
        editorBarWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                                         styleMask: [.resizable, .fullSizeContentView],
                                         backing: .buffered,
                                         defer: false)
        editorBarWindow.title = "Macsy Seciton Editor Bar"
        editorBarWindow.isOpaque = false
        editorBarWindow.backgroundColor = .clear
        editorBarWindow.titlebarAppearsTransparent = true
        editorBarWindow.isMovableByWindowBackground = true
        editorBarWindow.contentView = NSHostingView(rootView: EditorBarView(layoutWindow: self, onNewSection: onNewSection, onSave: onSave, onCancel: onCancel))
        editorBarWindow.orderOut(nil)
        editorBarWindow.level = .statusBar + 1
        
        var numberI = 1
        
        for i in 0..<sectionConfigs.count {
            let sectionConfig = sectionConfigs[i]
            let sectionWindow = SectionWindow(number: sectionConfig.number!, layoutWindow: self, sectionConfig: sectionConfig, onDelete: onSectionDelete)
            
            self.sectionConfigs[sectionConfig.number!] = sectionConfig
            sectionWindows.append(sectionWindow)
            
            if sectionConfig.number! > numberI {
                numberI = sectionConfig.number!
            }
        }
        
        window.orderOut(nil)
        editorBarWindow.orderOut(nil)
        
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved(event: event)
        }
    }
    
    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    func handleMouseMoved(event: NSEvent) {
        guard appSettings.showSnapResizersOnHover else { return }
        guard !isFitting else { return }
        guard !isEditing else { return }
        guard appSettings.snapResize else { return }
        guard userLayouts.currentLayout.layoutWindow === self else { return }
        
        let mouseLocation = NSEvent.mouseLocation
        let resizerRectsWithInfo = calculateSnapResizerRectsWithInfo()
        let proximityRects = resizerRectsWithInfo.filter { $0.rect.insetBy(dx: -snapResizerProximityThreshold, dy: -snapResizerProximityThreshold).contains(mouseLocation) }
        var newActiveKeys: Set<String> = []
        
        for info in proximityRects {
            let key = rectKey(info.rect)
            
            newActiveKeys.insert(key)
            
            if activeSnapResizers[key] == nil {
                let snapResizer = SnapResizer(width: info.rect.width,
                                              height: info.rect.height,
                                              relatedSections: info.relatedSections,
                                              mode: info.mode,
                                              isMouseOverResizer: true)
                
                snapResizer.setFrame(info.rect, display: true, animate: false)
                snapResizer.alphaValue = 0
                snapResizer.orderFront(nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.35
                    snapResizer.animator().alphaValue = 1
                }
                
                sectionResizers.append(snapResizer)
                activeSnapResizers[key] = snapResizer
            }
        }
        
        for (key, snapResizer) in activeSnapResizers {
            if !newActiveKeys.contains(key) {
                snapResizer.orderOut(nil)
            }
        }
        
        activeSnapResizers = activeSnapResizers.filter { newActiveKeys.contains($0.key) }
        sectionResizers = sectionResizers.filter { resizer in
            activeSnapResizers.values.contains(where: { $0 === resizer })
        }
    }

    func rectKey(_ rect: NSRect) -> String {
        return String(format: "%.1f,%.1f,%.1f,%.1f", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
    }

    func calculateSnapResizerRectsWithInfo() -> [(rect: NSRect, relatedSections: [RelatedSection], mode: SnapResizerMode)] {
        var result: [(rect: NSRect, relatedSections: [RelatedSection], mode: SnapResizerMode)] = []
        let verticalButtonWidth: CGFloat = 8
        let verticalButtonHeight: CGFloat = 50
        let horizontalButtonWidth: CGFloat = 50
        let horizontalButtonHeight: CGFloat = 8
        
        for sectionWindow in sectionWindows {
            let sectionFrame = sectionWindow.window.frame
            for otherSectionWindow in sectionWindows where otherSectionWindow !== sectionWindow {
                let otherSectionFrame = otherSectionWindow.window.frame
                let sectionRight = sectionFrame.maxX
                let sectionTop = sectionFrame.minY
                let sectionBottom = sectionFrame.maxY
                let otherLeft = otherSectionFrame.minX
                let otherTop = otherSectionFrame.minY
                let otherBottom = otherSectionFrame.maxY
                
                if abs(sectionRight - otherLeft) <= appSettings.snapResizeThreshold &&
                    (abs(sectionTop - otherTop) <= appSettings.snapResizeThreshold || abs(sectionBottom - otherBottom) <= appSettings.snapResizeThreshold)
                {
                    let buttonX = ((sectionRight + otherLeft) / 2) - (verticalButtonWidth / 2)
                    let topY = min(sectionFrame.maxY, otherSectionFrame.maxY)
                    let bottomY = max(sectionFrame.minY, otherSectionFrame.minY)
                    let buttonY = ((topY + bottomY) / 2) - (verticalButtonHeight / 2)
                    let xGap = abs(sectionRight - otherLeft)
                    let xGapToButton: CGFloat = xGap / 2
                    var relatedSections: [RelatedSection] = []
                    for possibleRelatedWindow in sectionWindows {
                        let possibleFrame = possibleRelatedWindow.window.frame
                        if abs(sectionRight - possibleFrame.minX) <= appSettings.snapResizeThreshold ||
                            abs(otherLeft - possibleFrame.maxX) <= appSettings.snapResizeThreshold {
                            relatedSections.append(.init(sectionWindow: possibleRelatedWindow,
                                                         direction: (possibleFrame.minX + (possibleFrame.width / 2)) < buttonX ? .left : .right,
                                                         gapToButton: xGapToButton))
                        }
                    }
                    let rect = NSRect(x: buttonX, y: buttonY, width: verticalButtonWidth, height: verticalButtonHeight)
                    result.append((rect, relatedSections, .vertical))
                }
            }
            for otherSectionWindow in sectionWindows where otherSectionWindow !== sectionWindow {
                let otherSectionFrame = otherSectionWindow.window.frame
                let sectionLeft = sectionFrame.minX
                let sectionRight = sectionFrame.maxX
                let sectionBottom = sectionFrame.minY
                let otherLeft = otherSectionFrame.minX
                let otherRight = otherSectionFrame.maxX
                let otherTop = otherSectionFrame.maxY
                
                if abs(sectionBottom - otherTop) <= appSettings.snapResizeThreshold &&
                   (abs(sectionLeft - otherLeft) <= appSettings.snapResizeThreshold || abs(sectionRight - otherRight) <= appSettings.snapResizeThreshold)
                {
                    let buttonY = ((sectionBottom + otherTop) / 2) - (horizontalButtonHeight / 2)
                    let leftX = min(sectionFrame.maxX, otherSectionFrame.maxX)
                    let rightX = max(sectionFrame.minX, otherSectionFrame.minX)
                    let buttonX = ((leftX + rightX) / 2) - (horizontalButtonWidth / 2)
                    let yGap = abs(sectionBottom - otherTop)
                    let yGapToButton: CGFloat = yGap / 2
                    var relatedSections: [RelatedSection] = []
                    for possibleRelatedWindow in sectionWindows {
                        let possibleFrame = possibleRelatedWindow.window.frame
                        if abs(sectionBottom - possibleFrame.maxY) <= appSettings.snapResizeThreshold ||
                           abs(otherTop - possibleFrame.minY) <= appSettings.snapResizeThreshold
                        {
                            relatedSections.append(.init(sectionWindow: possibleRelatedWindow,
                                                         direction: (possibleFrame.minY + (possibleFrame.height / 2)) < buttonY ? .bottom : .top,
                                                         gapToButton: yGapToButton))
                        }
                    }
                    let rect = NSRect(x: buttonX, y: buttonY, width: horizontalButtonWidth, height: horizontalButtonHeight)
                    result.append((rect, relatedSections, .horizontal))
                }
            }
        }
        return result
    }
    
    func onSectionDelete(unowned sectionWindow: SectionWindow) {
        let number = sectionWindow.number
        
        sectionWindow.window.orderOut(nil)
        sectionWindow.editorWindow.orderOut(nil)
        
        let isUnsaved = unsavedNewSectionWindows.contains(where: { $0.number == number })
        
        if !isUnsaved {
            unsavedRemovedSectionWindows.append(sectionWindow)
        }
        
        sectionConfigs.removeValue(forKey: number)
        unsavedNewSectionConfigs.removeValue(forKey: number)
        
        sectionWindows.removeAll { $0.number == number }
        unsavedNewSectionWindows.removeAll { $0.number == number }
    }
    
    func onNewSection() {
        let number = nextNumber
        var newSectionConfig = SectionConfig.defaultSection
        newSectionConfig.number = number
        let sectionWindow = SectionWindow(number: number, layoutWindow: self, sectionConfig: newSectionConfig, onDelete: onSectionDelete)
        sectionWindows.append(sectionWindow)
        
        sectionWindow.editorWindow.orderFront(nil)
        
        unsavedNewSectionWindows.append(sectionWindow)
        unsavedNewSectionConfigs[sectionWindow.number] = newSectionConfig
    }
    
    func onSave() {
        let focusedScreen = getFocusedScreen()
        
        for number in unsavedNewSectionConfigs.keys {
            guard let newSectionConfig = unsavedNewSectionConfigs[number] else { continue }
            sectionConfigs[number] = newSectionConfig
        }

        for number in sectionConfigs.keys {
            guard var sectionConfig = sectionConfigs[number] else { continue }
            guard let sectionWindow = sectionWindows.first(where: { $0.number == number }) else { continue }
            
            let width = sectionWindow.editorWindow.frame.size.width
            let height = sectionWindow.editorWindow.frame.size.height
            
            var x: CGFloat
            let y: CGFloat
            
            var screenSize: CGSize
            
            if let screen = sectionWindow.editorWindow.screen {
                let windowFrame = sectionWindow.editorWindow.frame
                let screenFrame = screen.frame
                screenSize = screenFrame.size
                
                x = windowFrame.origin.x - screenFrame.origin.x
                y = windowFrame.origin.y - screenFrame.origin.y
            } else {
                guard let focusedScreen else { continue }
                
                screenSize = focusedScreen.frame.size
                
                x = sectionWindow.editorWindow.frame.origin.x
                y = sectionWindow.editorWindow.frame.origin.y
            }
            
            sectionConfig.heightPercentage = height / screenSize.height
            sectionConfig.widthPercentage = width / screenSize.width
            sectionConfig.xPercentage = x / screenSize.width
            sectionConfig.yPercentage = y / screenSize.height
            
            self.sectionConfigs[number] = sectionConfig
            sectionWindow.reset(sectionConfig: sectionConfig)
        }
        
        userLayouts.layouts[name]?.sectionConfigs = sectionConfigs
        
        userLayouts.save()
        
        unsavedNewSectionConfigs.removeAll()
        unsavedNewSectionWindows.removeAll()
        unsavedRemovedSectionWindows.removeAll()
        
        macsyStopEditing()
        
        userLayouts.layouts[name]?.reArrange()
    }
    
    func onCancel() {
        macsyStopEditing()
    }
    
    func show(showLayouts: Bool = true, showSnapResizers: Bool = false) {
        let wasShwon = isShown
        isShown = true
        
        if !wasShwon {
            window.alphaValue = 0
            window.orderFront(nil)
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                window.animator().alphaValue = 1
            }
        } else {
            window.alphaValue = 1
            window.orderFront(nil)
        }
        
        editorBarWindow.orderOut(nil)
        
        if showLayouts {
            if let focusedScreen = getFocusedScreen() {
                window.setFrame(focusedScreen.visibleFrame, display: true, animate: false)
            }
            
            let sortedSectionWindows = sectionWindows.sorted { 
                let frame1 = $0.window.frame
                let frame2 = $1.window.frame
                return (frame1.width * frame1.height) > (frame2.width * frame2.height)
            }
            
            for sectionWindow in sortedSectionWindows {
                sectionWindow.editorWindow.orderOut(nil)
                sectionWindow.reset(sectionConfig: sectionWindow.sectionConfig)
                sectionWindow.window.alphaValue = 0
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.35
                    sectionWindow.window.animator().alphaValue = 1
                }
                
                sectionWindow.window.orderFrontRegardless()
            }
            
            for sectionResizer in sectionResizers {
                sectionResizer.alphaValue = 0
                sectionResizer.orderFront(nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.35
                    sectionResizer.animator().alphaValue = 1
                }
            }
        }
        
        if appSettings.snapResize && showSnapResizers {
            let verticalButtonWidth: CGFloat = 8
            let verticalButtonHeight: CGFloat = 50
            let horizontalButtonWidth: CGFloat = 50
            let horizontalButtonHeight: CGFloat = 8
            
            sectionResizers = sectionResizers.filter { $0.isMouseOverResizer }
            
            for sectionWindow in sectionWindows {
                let sectionFrame = sectionWindow.window.frame
                for otherSectionWindow in sectionWindows where otherSectionWindow !== sectionWindow {
                    let otherSectionFrame = otherSectionWindow.window.frame
                    let sectionRight = sectionFrame.maxX
                    let sectionTop = sectionFrame.minY
                    let sectionBottom = sectionFrame.maxY
                    let otherLeft = otherSectionFrame.minX
                    let otherTop = otherSectionFrame.minY
                    let otherBottom = otherSectionFrame.maxY
                    
                    if abs(sectionRight - otherLeft) <= appSettings.snapResizeThreshold &&
                        (abs(sectionTop - otherTop) <= appSettings.snapResizeThreshold || abs(sectionBottom - otherBottom) <= appSettings.snapResizeThreshold)
                    {
                        let buttonX = ((sectionRight + otherLeft) / 2) - (verticalButtonWidth / 2)
                        let topY = min(sectionFrame.maxY, otherSectionFrame.maxY)
                        let bottomY = max(sectionFrame.minY, otherSectionFrame.minY)
                        let buttonY = ((topY + bottomY) / 2) - (verticalButtonHeight / 2)
                        let xGap = abs(sectionRight - otherLeft)
                        let xGapToButton: CGFloat = xGap / 2
                        var relatedSections: [RelatedSection] = []
                        for possibleRelatedWindow in sectionWindows {
                            let possibleFrame = possibleRelatedWindow.window.frame
                            if abs(sectionRight - possibleFrame.minX) <= appSettings.snapResizeThreshold ||
                                abs(otherLeft - possibleFrame.maxX) <= appSettings.snapResizeThreshold {
                                relatedSections.append(.init(sectionWindow: possibleRelatedWindow,
                                                             direction: (possibleFrame.minX + (possibleFrame.width / 2)) < buttonX ? .left : .right,
                                                             gapToButton: xGapToButton))
                            }
                        }
                        
                        let sectionResizer = SnapResizer(width: verticalButtonWidth,
                                                         height: verticalButtonHeight,
                                                         relatedSections: relatedSections,
                                                         mode: .vertical)
                        sectionResizer.setFrame(NSRect(x: buttonX, y: buttonY, width: verticalButtonWidth, height: verticalButtonHeight), display: true, animate: false)
                        sectionResizer.alphaValue = 0
                        sectionResizer.orderFront(nil)
                        
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.35
                            sectionResizer.animator().alphaValue = 1
                        }
                        
                        sectionResizers.append(sectionResizer)
                    }
                }
                
                for otherSectionWindow in sectionWindows where otherSectionWindow !== sectionWindow {
                    let otherSectionFrame = otherSectionWindow.window.frame
                    let sectionLeft = sectionFrame.minX
                    let sectionRight = sectionFrame.maxX
                    let sectionBottom = sectionFrame.minY
                    let otherLeft = otherSectionFrame.minX
                    let otherRight = otherSectionFrame.maxX
                    let otherTop = otherSectionFrame.maxY
                    
                    if abs(sectionBottom - otherTop) <= appSettings.snapResizeThreshold &&
                       (abs(sectionLeft - otherLeft) <= appSettings.snapResizeThreshold || abs(sectionRight - otherRight) <= appSettings.snapResizeThreshold)
                    {
                        let buttonY = ((sectionBottom + otherTop) / 2) - (horizontalButtonHeight / 2)
                        let leftX = min(sectionFrame.maxX, otherSectionFrame.maxX)
                        let rightX = max(sectionFrame.minX, otherSectionFrame.minX)
                        let buttonX = ((leftX + rightX) / 2) - (horizontalButtonWidth / 2)
                        let yGap = abs(sectionBottom - otherTop)
                        let yGapToButton: CGFloat = yGap / 2
                        var relatedSections: [RelatedSection] = []
                        
                        for possibleRelatedWindow in sectionWindows {
                            let possibleFrame = possibleRelatedWindow.window.frame
                            if abs(sectionBottom - possibleFrame.maxY) <= appSettings.snapResizeThreshold ||
                               abs(otherTop - possibleFrame.minY) <= appSettings.snapResizeThreshold
                            {
                                relatedSections.append(.init(sectionWindow: possibleRelatedWindow,
                                                             direction: (possibleFrame.minY + (possibleFrame.height / 2)) < buttonY ? .bottom : .top,
                                                             gapToButton: yGapToButton))
                            }
                        }
                        
                        let sectionResizer = SnapResizer(width: horizontalButtonWidth, height: horizontalButtonHeight, relatedSections: relatedSections, mode: .horizontal)
                        sectionResizer.setFrame(NSRect(x: buttonX, y: buttonY, width: horizontalButtonWidth, height: horizontalButtonHeight), display: true, animate: false)
                        sectionResizer.alphaValue = 0
                        sectionResizer.orderFront(nil)
                        
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.35
                            sectionResizer.animator().alphaValue = 1
                        }
                        
                        sectionResizers.append(sectionResizer)
                    }
                }
            }
        }
    }

    func hide() {
        isShown = false
        
        for sectionResizer in sectionResizers {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                sectionResizer.animator().alphaValue = 0
            }, completionHandler: {
                sectionResizer.orderOut(nil)
            })
        }
        sectionResizers = sectionResizers.filter { $0.isMouseOverResizer }
        
        for sectionWindow in sectionWindows {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                sectionWindow.window.animator().alphaValue = 0
            }, completionHandler: {
                sectionWindow.window.orderOut(nil)
                sectionWindow.editorWindow.orderOut(nil)
            })
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            window.animator().alphaValue = 0
        }, completionHandler: {
            self.window.orderOut(nil)
        })
        
        editorBarWindow.orderOut(nil)
    }
    
    func startEditing() {
        isEditing = true
        
        window.orderFront(nil)
        
        if let focusedScreen = getFocusedScreen() {
            window.setFrame(focusedScreen.visibleFrame, display: true, animate: false)
            
            for sectionWindow in sectionWindows {
                sectionWindow.reset(sectionConfig: sectionWindow.sectionConfig)
                sectionWindow.startEditing()
            }
        } else {
            for sectionWindow in sectionWindows {
                sectionWindow.startEditing()
            }
        }
        
        editorBarWindow.orderFront(nil)
        editorBarWindow.level = .statusBar + 1
        editorBarWindow.center()
    }
    
    func stopEditing() {
        isEditing = false
        
        for sectionWindow in sectionWindows {
            sectionWindow.stopEditing()
        }
        
        window.orderOut(nil)
        editorBarWindow.orderOut(nil)
        
        for sectionWindow in unsavedRemovedSectionWindows {
            let number = sectionWindow.number
            let sectionConfig = sectionWindow.sectionConfig
            
            sectionConfigs[number] = sectionConfig
            sectionWindows.append(sectionWindow)
        }
        
        unsavedRemovedSectionWindows.removeAll()
        
        for number in sectionConfigs.keys {
            let sectionConfig = sectionConfigs[number]
            guard let sectionConfig else { continue }
            let sectionWindow = sectionWindows.first(where: { $0.number == number })
            guard let sectionWindow else { continue }
            
            sectionWindow.reset(sectionConfig: sectionConfig)
        }
        
        for unsavedSectionWindow in unsavedNewSectionWindows {
            sectionWindows.removeAll(where: { $0.number == unsavedSectionWindow.number })
        }
        
        unsavedNewSectionConfigs.removeAll()
        unsavedNewSectionWindows.removeAll()
    }
    
    @discardableResult
    func toggleEditing() -> Bool {
        if !isEditing {
            macssyStartEditing()
        } else {
            macsyStopEditing()
        }
        return isEditing
    }
    
    func closeAllWindows() {
        for sectionWindow in sectionWindows {
            sectionWindow.window.close()
            sectionWindow.editorWindow.close()
        }
        
        window.close()
        editorBarWindow.close()
    }
}

enum RelatedSectionDirection {
    case left
    case right
    case top
    case bottom
}

class RelatedSection {
    let sectionWindow: SectionWindow
    let direction: RelatedSectionDirection
    let gapToButton: CGFloat
    
    init(sectionWindow: SectionWindow, direction: RelatedSectionDirection, gapToButton: CGFloat) {
        self.sectionWindow = sectionWindow
        self.direction = direction
        self.gapToButton = gapToButton
    }
}

enum SnapResizerMode {
    case vertical
    case horizontal
}

class SnapResizer: NSWindow {
    var relatedSections: [RelatedSection] = []
    var mode: SnapResizerMode = .vertical
    
    var resizerX: CGFloat = 0
    var resizerY: CGFloat = 0
    
    var draggedOnce = false
    
    var resizeDelay = 0.1
    var resizeTask: DispatchWorkItem? = nil
    
    var isMouseOverResizer = false
    
    init(width: CGFloat, height: CGFloat, relatedSections: [RelatedSection], mode: SnapResizerMode, isMouseOverResizer: Bool = false) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        
        self.mode = mode
        self.isMouseOverResizer = isMouseOverResizer
        
        isOpaque = false
        backgroundColor = .clear
        title = "Macsy Live Snap Resizer"
        hasShadow = true
        ignoresMouseEvents = false
        level = .statusBar + 1
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false

        contentView = NSHostingView(rootView: SnapResizerView(relatedSections: relatedSections,
                                                              isMouseOverResizer: isMouseOverResizer))
        
        self.relatedSections = relatedSections
    }
    
    override func mouseDown(with event: NSEvent) {
        isSnapResizing = true
        
        for sectionResizer in userLayouts.currentLayout.layoutWindow.sectionResizers
        where sectionResizer !== self {
            sectionResizer.orderOut(nil)
        }
        
        resizerX = frame.origin.x
        resizerY = frame.origin.y
        
        if isSnapResizing && isMouseOverResizer {
            userLayouts.currentLayout.layoutWindow.show()
        }
        
        for sectionWindow in (userLayouts.currentLayout.layoutWindow.sectionWindows.filter { sectionWindow in
            !relatedSections.contains(where: { $0.sectionWindow === sectionWindow })
        }) {
            sectionWindow.window.orderOut(nil)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        isSnapResizing = false
        
        if isSnapResizing && isMouseOverResizer {
            userLayouts.currentLayout.layoutWindow.hide()
        }
        
        if !draggedOnce {
            return
        }
        
        guard let focusedScreen = getFocusedScreen() else {
            if isSnapResizing && isMouseOverResizer {
                userLayouts.currentLayout.layoutWindow.hide()
            }
            
            return
        }
        
        let sectionConfigs = userLayouts.currentLayout.sectionConfigs
        
        for relatedSection in relatedSections {
            let sectionWindow = relatedSection.sectionWindow
            guard let sectionConfig = sectionConfigs[relatedSection.sectionWindow.number]
            else { continue }
            
            let newSectionConfig = sectionConfig.getUpdated(for: sectionWindow.window,
                                                            on: focusedScreen)
            
            userLayouts.currentLayout.sectionConfigs[relatedSection.sectionWindow.number] = newSectionConfig
            sectionWindow.reset(sectionConfig: newSectionConfig)
        }
        
        userLayouts.save()
        
        isSnapResizing = false
        
        if isSnapResizing && isMouseOverResizer {
            userLayouts.currentLayout.layoutWindow.hide()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        draggedOnce = true
        
        guard let focusedScreen = getFocusedScreen() else { return }
        let focusedScreenNumber = NSScreen.screens.firstIndex(of: focusedScreen)
        
        resizerX += event.deltaX
        resizerY -= event.deltaY

        if mode == .vertical {
            setFrameOrigin(NSPoint(x: resizerX, y: frame.origin.y))
        } else {
            setFrameOrigin(NSPoint(x: frame.origin.x, y: resizerY))
        }

        for relatedSection in relatedSections {
            var sectionFrame = relatedSection.sectionWindow.window.frame
            
            switch relatedSection.direction {
            case .left:
                let newWidth = max(0, sectionFrame.width + event.deltaX)
                sectionFrame.size.width = newWidth
                break
                
            case .right:
                let newX = sectionFrame.origin.x + event.deltaX
                let newWidth = max(0, sectionFrame.width - event.deltaX)
                sectionFrame.origin.x = newX
                sectionFrame.size.width = newWidth
                break
                
            case .top:
                let newY = sectionFrame.origin.y - event.deltaY
                let newHeight = max(0, sectionFrame.size.height + event.deltaY)
                sectionFrame.origin.y = newY
                sectionFrame.size.height = newHeight
                break
                
            case .bottom:
                let newHeight = max(0, sectionFrame.size.height - event.deltaY)
                sectionFrame.size.height = newHeight
                break
            }
            
            relatedSection.sectionWindow.window.setFrame(sectionFrame, display: true, animate: false)
            
        }
        
        resizeTask?.cancel()
        
        resizeTask = DispatchWorkItem {
            for relatedSection in self.relatedSections {
                for (windowId, sectionNumber) in PlacedWindows.windows {
                    guard let element = PlacedWindows.elements[windowId] else { continue }
                    
                    let sectionWindow = relatedSection.sectionWindow
                    
                    if sectionWindow.number != sectionNumber { continue }
                    if PlacedWindows.layouts[windowId] != relatedSection.sectionWindow.layoutWindow.name { continue }
                    
                    guard let screenNumber = PlacedWindows.screens[windowId] else { continue }
                    if NSScreen.screens.count <= screenNumber { continue }
                    
                    if focusedScreenNumber != screenNumber {
                        let screen = NSScreen.screens[screenNumber]
                        let sectionConfig = sectionWindow.sectionConfig.getUpdated(for: sectionWindow.window,
                                                                                   on: focusedScreen)
                        
                        moveWindowToMatch(element: element,
                                          targetWindow: sectionWindow.window,
                                          targetScreen: screen,
                                          sectionConfig: sectionConfig)
                    } else {
                        moveWindowToMatch(element: element,
                                          targetWindow: sectionWindow.window)
                    }
                }
            }
        }
        
        if let resizeTask {
            DispatchQueue.main.asyncAfter(deadline: .now() + resizeDelay, execute: resizeTask)
        }
    }
}

struct SnapResizerView: View {
    var relatedSections: [RelatedSection] = []
    var isMouseOverResizer = false
    
    @State private var isHovering = false
    @State private var hoverWorkItem: DispatchWorkItem?
    let hoverDelay: TimeInterval = 0.3
    
    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(Color.white.opacity(0.2))
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(BlurredWindowBackground(material: .hudWindow, blendingMode: .behindWindow).cornerRadius(10))
                .cornerRadius(.infinity)
                .contentShape(.rect)
                .onHover { hovering in
                    guard isMouseOverResizer else { return }
                    
                    if hovering {
                        isHovering = true
                        
                        let workItem = DispatchWorkItem {
                            if isHovering {
                                NSCursor.resizeUpDown.push()
                                if !isSnapResizing {
                                    userLayouts.currentLayout.layoutWindow.show()
                                    
                                    for sectionWindow in (userLayouts.currentLayout.layoutWindow.sectionWindows.filter { sectionWindow in
                                        !relatedSections.contains(where: { $0.sectionWindow === sectionWindow })
                                    }) {
                                        sectionWindow.window.orderOut(nil)
                                    }
                                }
                            }
                        }
                        
                        hoverWorkItem?.cancel()
                        hoverWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: workItem)
                    } else {
                        isHovering = false
                        hoverWorkItem?.cancel()
                        NSCursor.pop()
                        if !isSnapResizing {
                            userLayouts.currentLayout.layoutWindow.hide()
                        }
                    }
                }
        }
    }
}

#Preview {
}

