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
    @State var number: Int = 0
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Text(String(number))
                    .font(.system(size: 50))
                    .foregroundColor(Color(NSColor.selectedTextBackgroundColor))
                    .padding(50)
                    .background(Circle().fill(Color(NSColor.selectedTextBackgroundColor).opacity(0.25)))
                    .overlay(Circle().stroke(Color(NSColor.selectedTextBackgroundColor).opacity(0.5), lineWidth: 4))
            }.frame(width: geometry.size.width, height: geometry.size.height)
             .background(Color(NSColor.selectedTextBackgroundColor).opacity(0.1))
             .border(Color(NSColor.selectedTextBackgroundColor).opacity(0.75), width: 5)
             .cornerRadius(7)
        }
    }
}

class EditorSectionView: NSView {
    var onDelete: (() -> Void)?
    
    var number: Int = 0 {
        didSet {
            label.stringValue = String(number)
        }
    }
    
    private let label = NSTextField(labelWithString: "")
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
        label.font = NSFont.systemFont(ofSize: 50)
        label.textColor = NSColor.selectedTextBackgroundColor
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.backgroundColor = .clear
        addSubview(label)

        circleView.wantsLayer = true
        circleView.layer = CALayer()
        circleView.layer?.cornerRadius = 75
        circleView.layer?.masksToBounds = true
        circleView.layer?.backgroundColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.25).cgColor
        circleView.layer?.borderColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.5).cgColor
        circleView.layer?.borderWidth = 4
        addSubview(circleView)
        
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")?.withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        deleteButton.frame.size = CGSize(width: 80, height: 80)
        deleteButton.imagePosition = .imageOnly
        deleteButton.contentTintColor = .white
        deleteButton.isBordered = false
        deleteButton.wantsLayer = true
        deleteButton.layer?.backgroundColor = NSColor.selectedTextBackgroundColor.cgColor
        deleteButton.layer?.cornerRadius = 8
        deleteButton.layer?.masksToBounds = true
        deleteButton.target = self
        deleteButton.action = #selector(deleteSection)
        addSubview(deleteButton)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        circleView.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            circleView.widthAnchor.constraint(equalToConstant: 150),
            circleView.heightAnchor.constraint(equalTo: circleView.widthAnchor),
            
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            deleteButton.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])
    }
    
    @objc private func deleteSection() {
        onDelete?()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
                
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.1).setFill()
        dirtyRect.fill()
        
        let borderPath = NSBezierPath(roundedRect: dirtyRect, xRadius: 7, yRadius: 7)
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.75).setStroke()
        borderPath.lineWidth = 5
        borderPath.stroke()
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

class SectionWindow: Hashable {
    var number: Int = 0
    var editorWindow: NSWindow!
    var layoutWindow: LayoutWindow!
    var window: NSWindow!
    var sectionConfig: SectionConfig
    
    var isEditing: Bool { layoutWindow.isEditing }
    
    let onDelete: ((SectionWindow) -> Void)

    init(number: Int, layoutWindow: LayoutWindow, sectionConfig: SectionConfig, onDelete: @escaping ((SectionWindow) -> Void)) {
        self.number = number
        self.sectionConfig = sectionConfig
        self.layoutWindow = layoutWindow
        self.onDelete = onDelete
        
        let contentRect = getConfiguredContentRect(sectionConfig: sectionConfig)

        window = NSWindow(contentRect: contentRect,
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.title = "Macsy Section"
        window.contentView = NSHostingView(rootView: SectionView(number: number))
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.level = .statusBar - 2

        layoutWindow.window.addChildWindow(window, ordered: .above)
        
        editorWindow = NSWindow(contentRect: contentRect,
                                styleMask: [.resizable, .fullSizeContentView],
                                backing: .buffered,
                                defer: false)
        editorWindow.title = "Macsy Editor Section"
        editorWindow.isOpaque = false
        editorWindow.backgroundColor = .clear
        editorWindow.titlebarAppearsTransparent = true
        editorWindow.isMovableByWindowBackground = true
        editorWindow.level = .statusBar - 1
        
        let editorSectionView = EditorSectionView(frame: NSRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height))
        editorSectionView.onDelete = { [unowned self] in
            onDelete(self)
        }
        editorSectionView.number = number
        editorWindow.contentView = editorSectionView
        
        layoutWindow.window.addChildWindow(editorWindow, ordered: .above)
        
        window.orderOut(nil)
        editorWindow.orderOut(nil)
    }
    
    func getConfiguredContentRect(sectionConfig: SectionConfig) -> NSRect {
        guard let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else {
            return NSRect(x: 0, y: 0, width: 800, height: 600)
        }

        let screenFrame = focusedScreen.frame

        let width = screenFrame.width * sectionConfig.widthPercentage
        let height = screenFrame.height * sectionConfig.heightPercentage

        let x = screenFrame.origin.x + (screenFrame.width * sectionConfig.xPercentage)
        let y = screenFrame.origin.y + (screenFrame.height * sectionConfig.yPercentage)

        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    func reset(sectionConfig: SectionConfig) {
        self.sectionConfig = sectionConfig
        
        let contentRect = getConfiguredContentRect(sectionConfig: sectionConfig)
        window.setFrame(contentRect, display: true, animate: false)
        editorWindow.setFrame(contentRect, display: true, animate: false)
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
        }.frame(height: 50)
         .fixedSize(horizontal: false, vertical: true)
         .background(BlurredWindowBackground(material: .hudWindow, blendingMode: .behindWindow).cornerRadius(10).padding(.horizontal, 7))
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
    
    var numberI = 1
    
    var unsavedNewSectionWindows: [SectionWindow] = []
    var unsavedNewSectionConfigs: [Int:SectionConfig] = [:]
    var unsavedRemovedSectionWindows: [SectionWindow] = []
    
    var sectionResizers: [SnapResizer] = []

    init(name: String, sectionConfigs: [SectionConfig]) {
        self.name = name
        
        let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
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
        
        for i in 0..<sectionConfigs.count {
            let sectionConfig = sectionConfigs[i]
            let sectionWindow = SectionWindow(number: numberI, layoutWindow: self, sectionConfig: sectionConfig, onDelete: onSectionDelete)
            
            self.sectionConfigs[numberI] = sectionConfig
            sectionWindows.append(sectionWindow)
            
            numberI += 1
        }
        
        window.orderOut(nil)
        editorBarWindow.orderOut(nil)
    }
    
    func onSectionDelete(unowned sectionWindow: SectionWindow) {
        sectionWindow.window.orderOut(nil)
        sectionWindow.editorWindow.orderOut(nil)
        
        sectionConfigs.removeValue(forKey: sectionWindow.number)
        unsavedNewSectionConfigs.removeValue(forKey: sectionWindow.number)
        
        sectionWindows.removeAll { $0.number == sectionWindow.number }
        unsavedNewSectionWindows.removeAll { $0.number == sectionWindow.number }
        
        unsavedRemovedSectionWindows.append(sectionWindow)
    }
    
    func onNewSection() {
        let newSectionConfig = SectionConfig.defaultSection
        let sectionWindow = SectionWindow(number: numberI, layoutWindow: self, sectionConfig: newSectionConfig, onDelete: onSectionDelete)
        sectionWindows.append(sectionWindow)
        numberI += 1
        
        sectionWindow.editorWindow.orderFront(nil)
        
        unsavedNewSectionWindows.append(sectionWindow)
        unsavedNewSectionConfigs[sectionWindow.number] = newSectionConfig
    }
    
    func onSave() {
        guard let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else { return }
        let screenSize = focusedScreen.frame
        
        for number in unsavedNewSectionConfigs.keys {
            guard let newSectionConfig = unsavedNewSectionConfigs[number] else { continue }
            guard let newSectionWindow = unsavedNewSectionWindows.first(where: { $0.number == number }) else { continue }
            sectionConfigs[number] = newSectionConfig
            sectionWindows.append(newSectionWindow)
        }

        for number in sectionConfigs.keys {
            guard var sectionConfig = sectionConfigs[number] else { continue }
            guard let sectionWindow = sectionWindows.first(where: { $0.number == number }) else { continue }
            
            let width = sectionWindow.editorWindow.frame.size.width
            let height = sectionWindow.editorWindow.frame.size.height
            let x = sectionWindow.editorWindow.frame.origin.x
            let y = sectionWindow.editorWindow.frame.origin.y
            
            sectionConfig.heightPercentage = height / screenSize.height
            sectionConfig.widthPercentage = width / screenSize.width
            sectionConfig.xPercentage = x / screenSize.width
            sectionConfig.yPercentage = y / screenSize.height
            
            self.sectionConfigs[number] = sectionConfig
            sectionWindow.reset(sectionConfig: sectionConfig)
        }
        
        userLayouts.layouts[name]?.sectionConfigs = Array(sectionConfigs.values)
        
        userLayouts.save()
        
        unsavedNewSectionConfigs.removeAll()
        unsavedNewSectionWindows.removeAll()
        unsavedRemovedSectionWindows.removeAll()
        
        macsyStopEditing()
    }
    
    func onCancel() {
        macsyStopEditing()
        
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
    
    func show(showSnapResizers: Bool = false) {
        window.orderFront(nil)
        editorBarWindow.orderOut(nil)
        
        if let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            window.setFrame(focusedScreen.visibleFrame, display: true, animate: false)
        }
        
        for sectionWindow in sectionWindows {
            sectionWindow.editorWindow.orderOut(nil)
            sectionWindow.reset(sectionConfig: sectionWindow.sectionConfig)
            sectionWindow.window.orderFront(nil)
        }
        
        let snapResizerThreshold: CGFloat = 100
        
        let verticalButtonWidth: CGFloat = 24
        let verticalButtonHeight: CGFloat = 50
        
        let horizontalButtonWidth: CGFloat = 75
        let horizontalButtonHeight: CGFloat = 10
        
        for sectionResizer in sectionResizers {
            sectionResizer.orderOut(nil)
        }
        
        sectionResizers = []
        
        if appSettings.snapResize && showSnapResizers {
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
                    
                    if abs(sectionRight - otherLeft) <= snapResizerThreshold &&
                       (abs(sectionTop - otherTop) <= snapResizerThreshold || abs(sectionBottom - otherBottom) <= snapResizerThreshold) {
                        let buttonX = ((sectionRight + otherLeft) / 2) - (verticalButtonWidth / 2)
                        
                        let topY = min(sectionFrame.maxY, otherSectionFrame.maxY)
                        let bottomY = max(sectionFrame.minY, otherSectionFrame.minY)
                        let buttonY = ((topY + bottomY) / 2) - (verticalButtonHeight / 2)
                        let xGap = abs(sectionRight - otherLeft)
                        let xGapToButton: CGFloat = xGap / 2
                        
                        var relatedSections: [RelatedSection] = [.init(sectionWindow: sectionWindow, direction: .left, gapToButton: xGapToButton)]
                        
                        for possibleRelatedWindow in sectionWindows where possibleRelatedWindow !== sectionWindow {
                            let possibleFrame = possibleRelatedWindow.window.frame
                            if abs(sectionRight - possibleFrame.minX) <= snapResizerThreshold {
                                let direction: RelatedSectionDirection = possibleFrame.maxX <= sectionFrame.maxX ? .left : .right
                                relatedSections.append(RelatedSection(sectionWindow: possibleRelatedWindow, direction: direction, gapToButton: xGapToButton))
                            } else if abs(otherLeft - possibleFrame.maxX) <= snapResizerThreshold {
                                let direction: RelatedSectionDirection = possibleFrame.minX >= sectionFrame.minX ? .left : .right
                                relatedSections.append(RelatedSection(sectionWindow: possibleRelatedWindow, direction: direction, gapToButton: xGapToButton))
                            }
                        }
                        
                        let sectionResizer = SnapResizer(width: verticalButtonWidth, height: verticalButtonHeight, relatedSections: relatedSections, mode: .vertical)
                        sectionResizer.setFrame(NSRect(x: buttonX, y: buttonY, width: verticalButtonWidth, height: verticalButtonHeight), display: true, animate: false)
                        sectionResizer.orderFront(nil)
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
                    
                    if abs(sectionBottom - otherTop) <= snapResizerThreshold &&
                       (abs(sectionLeft - otherLeft) <= snapResizerThreshold || abs(sectionRight - otherRight) <= snapResizerThreshold) {
                        let buttonY = ((sectionBottom + otherTop) / 2) - (horizontalButtonHeight / 2)
                        
                        let leftX = min(sectionFrame.maxX, otherSectionFrame.maxX)
                        let rightX = max(sectionFrame.minX, otherSectionFrame.minX)
                        let buttonX = ((leftX + rightX) / 2) - (horizontalButtonWidth / 2)
                        let yGap = abs(sectionBottom - otherTop)
                        let yGapToButton: CGFloat = yGap / 2
                        
                        var relatedSections: [RelatedSection] = [.init(sectionWindow: sectionWindow, direction: .top, gapToButton: yGapToButton)]
                        
                        for possibleRelatedWindow in sectionWindows where possibleRelatedWindow !== sectionWindow {
                            let possibleFrame = possibleRelatedWindow.window.frame
                            if abs(sectionBottom - possibleFrame.maxY) <= snapResizerThreshold {
                                let direction: RelatedSectionDirection = possibleFrame.minY >= sectionFrame.minY ? .top : .bottom
                                relatedSections.append(RelatedSection(sectionWindow: possibleRelatedWindow, direction: direction, gapToButton: yGapToButton))
                            } else if abs(otherTop - possibleFrame.minY) <= snapResizerThreshold {
                                let direction: RelatedSectionDirection = possibleFrame.maxY <= sectionFrame.maxY ? .top : .bottom
                                relatedSections.append(RelatedSection(sectionWindow: possibleRelatedWindow, direction: direction, gapToButton: yGapToButton))
                            }
                        }
                        
                        let sectionResizer = SnapResizer(width: horizontalButtonWidth, height: horizontalButtonHeight, relatedSections: relatedSections, mode: .horizontal)
                        sectionResizer.setFrame(NSRect(x: buttonX, y: buttonY, width: horizontalButtonWidth, height: horizontalButtonHeight), display: true, animate: false)
                        sectionResizer.orderFront(nil)
                        sectionResizers.append(sectionResizer)
                    }
                }
            }
        }
    }
    
    func hide() {
        for sectionResizer in sectionResizers {
            sectionResizer.orderOut(nil)
        }
        
        sectionResizers = []
        
        for sectionWindow in sectionWindows {
            sectionWindow.window.orderOut(nil)
            sectionWindow.editorWindow.orderOut(nil)
        }
        
        window.orderOut(nil)
        editorBarWindow.orderOut(nil)
    }
    
    func startEditing() {
        isEditing = true
        
        window.orderFront(nil)
        
        if let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
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
    
    init(width: CGFloat, height: CGFloat, relatedSections: [RelatedSection], mode: SnapResizerMode) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        
        self.mode = mode
        isOpaque = false
        backgroundColor = .clear
        title = "Macsy Live Snap Resizer"
        hasShadow = false
        ignoresMouseEvents = false
        level = .statusBar + 1
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false

        contentView = NSHostingView(rootView: ResizeLayer())
        
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
    }
    
    override func mouseUp(with event: NSEvent) {
        if !draggedOnce {
            isSnapResizing = false
            return
        }
        
        guard let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else { return }
        let screenSize = focusedScreen.frame
        
        let sectionConfigs = userLayouts.currentLayout.sectionConfigs
        
        for relatedSection in relatedSections {
            let sectionWindow = relatedSection.sectionWindow
            var sectionConfig = sectionConfigs[relatedSection.sectionWindow.number-1]
            
            let width = sectionWindow.window.frame.size.width
            let height = sectionWindow.window.frame.size.height
            let x = sectionWindow.window.frame.origin.x
            let y = sectionWindow.window.frame.origin.y
            
            sectionConfig.heightPercentage = height / screenSize.height
            sectionConfig.widthPercentage = width / screenSize.width
            sectionConfig.xPercentage = x / screenSize.width
            sectionConfig.yPercentage = y / screenSize.height
            
            userLayouts.currentLayout.sectionConfigs[relatedSection.sectionWindow.number-1] = sectionConfig
            sectionWindow.reset(sectionConfig: sectionConfig)
        }
        
        userLayouts.save()
        
        isSnapResizing = false
    }

    override func mouseDragged(with event: NSEvent) {
        draggedOnce = true
        
        guard let focusedScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else { return }
        let screenSize = focusedScreen.frame
        
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
                let newX = resizerX - relatedSection.gapToButton + (frame.width / 2)
                let newWidth = max(0, newX - sectionFrame.origin.x)
                sectionFrame.size.width = newWidth
                
            case .right:
                let newX = (resizerX + relatedSection.gapToButton) + (frame.width / 2)
                let newWidth = max(0, sectionFrame.maxX - newX)
                sectionFrame.origin.x = newX
                sectionFrame.size.width = newWidth
                
            case .top:
                let newY = resizerY + relatedSection.gapToButton + (frame.height / 2)
                let newHeight = max(0, sectionFrame.maxY - newY)
                sectionFrame.origin.y = newY
                sectionFrame.size.height = newHeight
                
            case .bottom:
                let newY = resizerY - relatedSection.gapToButton + (frame.height / 2)
                let newHeight = max(0, newY - sectionFrame.origin.y)
                sectionFrame.size.height = newHeight
            }
            
            relatedSection.sectionWindow.window.setFrame(sectionFrame, display: true)
            
            for (windowId, _) in PlacedWindows.windows {
                let sectionWindow = relatedSection.sectionWindow
                
                if sectionWindow.number != PlacedWindows.windows[windowId] { continue }
                
                let topLeftPosition = CGPoint(x: sectionWindow.window.frame.origin.x, y: screenSize.height - sectionWindow.window.frame.origin.y - sectionWindow.window.frame.height)
                let element = PlacedWindows.elements[windowId]
                let size = sectionWindow.window.frame.size
                
                resizeAndMoveWindow(element: element!, newPosition: topLeftPosition, newSize: size)
            }
        }
    }
}

struct ResizeLayer: View {
    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(Color.white.opacity(0.1))
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(BlurredWindowBackground(material: .hudWindow, blendingMode: .behindWindow).cornerRadius(10).padding(.horizontal, 7))
                .cornerRadius(.infinity)
        }
    }
}

#Preview {
    VStack {
        LayoutView(sections: [.init(number: 0)])
    }.frame(width: 200, height: 200)
}
