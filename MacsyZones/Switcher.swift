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

struct LayoutItem: Equatable {
    let name: String
    let layoutType: LayoutType
    
    let sections: [SectionConfig]

    init(name: String, layoutType: LayoutType, sections: [SectionConfig] = []) {
        self.name = name
        self.layoutType = layoutType
        self.sections = sections
    }

    static func == (lhs: LayoutItem, rhs: LayoutItem) -> Bool {
        lhs.name == rhs.name && lhs.layoutType == rhs.layoutType
    }
}

enum LayoutSwitcherMode {
    case direct
    case actual
}

class LayoutDockMouseState: ObservableObject {
    @Published var position: CGPoint = CGPoint(x: -10_000, y: -10_000)
    @Published var isExpanded: Bool = true
    @Published var hostWindowFrame: CGRect = .zero
}

private struct DockCentersKey: PreferenceKey {
    typealias Value = [String: CGRect]

    static var defaultValue: Value = [:]

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { $1 }
    }
}

struct LayoutSwitcher: View {
    @Binding var selectedLayoutName: String

    let layouts: [LayoutItem]

    @ObservedObject var mouseState: LayoutDockMouseState = LayoutDockMouseState()
    
    var mode: LayoutSwitcherMode = .direct
    var onHoldSelect: ((String) -> Void)? = nil
    
    @State private var internalMouseX: CGFloat = -10_000
    @State private var isMouseInside: Bool = false
    @State private var eventMonitor: Any? = nil
    @State private var itemRects: [String: CGRect] = [:]
    @State private var isVisible: Bool = false

    private final class DwellState {
        var workItem: DispatchWorkItem?
        var target: String?
    }

    @State private var dwell = DwellState()

    private var resolvedMouse: CGPoint { mouseState.position }

    private func ensureSelectionIsValid() {
        guard !layouts.isEmpty else { return }

        let existsInAllLayouts = userLayouts.layouts.keys.contains(selectedLayoutName)
        if !existsInAllLayouts {
            selectedLayoutName = layouts[0].name
        }
    }
    
    private func closestItem(at point: CGPoint) -> String? {
        guard point.x > 0, !itemRects.isEmpty else { return nil }

        for layout in layouts {
            if let rect = itemRects[layout.name], rect.contains(point) {
                return layout.name
            }
        }
        
        return nil
    }

    private func magnification(for name: String) -> CGFloat {
        guard let rect = itemRects[name] else { return 1.0 }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let mouse = resolvedMouse
        let distance = hypot(mouse.x - center.x, mouse.y - center.y)
        let radius: CGFloat = 90

        guard distance < radius else { return 1.0 }

        let t = 1.0 - distance / radius

        return 1.0 + 0.45 * t * t
    }

    var body: some View {
        Group {
            if layouts.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.slash")
                    Text("No layouts")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .bottom, spacing: mouseState.isExpanded ? 10 : 6) {
                    ForEach(layouts, id: \.name) { layout in
                        let compact = !mouseState.isExpanded
                        let scale = compact ? 1.0 : magnification(for: layout.name)
                        DockItem(
                            layout: layout,
                            isSelected: mode == .direct && selectedLayoutName == layout.name,
                            scale: scale,
                            isDwelling: dwell.target == layout.name,
                            isCompact: compact
                        )
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: DockCentersKey.self,
                                    value: {
                                        let wf = mouseState.hostWindowFrame != .zero
                                            ? mouseState.hostWindowFrame
                                            : (NSApp.keyWindow?.frame ?? .zero)
                                        let gf = geo.frame(in: .global)
                                        return [layout.name: CGRect(
                                            x: wf.origin.x + gf.minX,
                                            y: wf.origin.y + wf.height - gf.maxY,
                                            width: gf.width,
                                            height: gf.height
                                        )]
                                    }()
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, mouseState.isExpanded ? 32 : 16)
                .padding(.vertical, mouseState.isExpanded ? 24 : 12)
                .onPreferenceChange(DockCentersKey.self) { rects in
                    itemRects = rects
                }
            }
        }
        .modifier {
            if #available(macOS 26.0, *) {
                $0.glassEffect()
            } else {
                $0.background(BlurredWindowBackground(material: .hudWindow,
                                                      blendingMode: .behindWindow)
                    .cornerRadius(16).padding(.horizontal, 10))
            }
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.85, anchor: .top)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .onChange(of: mouseState.position) { newPos in
            guard let onHoldSelect = onHoldSelect else { return }
            
            guard mouseState.isExpanded else {
                dwell.workItem?.cancel()
                dwell.workItem = nil
                dwell.target = nil
                return
            }

            let target = closestItem(at: newPos)

            guard target != dwell.target else { return }
            
            dwell.workItem?.cancel()
            dwell.workItem = nil
            dwell.target = target

            if let name = target, mode == .actual || name != selectedLayoutName {
                let work = DispatchWorkItem { [weak dwell = self.dwell] in
                    dwell?.target = nil
                    onHoldSelect(name)
                }

                dwell.workItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            } else {
                dwell.target = nil
            }
        }
        .onHover { hovering in
            isMouseInside = hovering

            if !hovering {
                mouseState.position = CGPoint(x: -10_000, y: -10_000)
                dwell.workItem?.cancel()
                dwell.workItem = nil
                dwell.target = nil
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                isVisible = true
            }

            ensureSelectionIsValid()

            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
                if isMouseInside {
                    mouseState.position = NSEvent.mouseLocation
                }

                return event
            }
        }
        .onDisappear {
            dwell.workItem?.cancel()
            dwell.workItem = nil
            dwell.target = nil

            if let m = eventMonitor {
                NSEvent.removeMonitor(m)
                eventMonitor = nil
            }
        }
    }
}

struct LayoutPreviewIcon: View {
    let sections: [SectionConfig]
    let isSelected: Bool
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var tileBg: Color {
        isSelected ? Color.accentColor.opacity(0.22)
                   : (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.12))
    }

    private var zoneFill: Color {
        isSelected ? Color.accentColor.opacity(0.55)
                   : (colorScheme == .dark ? Color.white.opacity(0.38) : Color.black.opacity(0.30))
    }

    private var zoneStroke: Color {
        isSelected ? Color.accentColor.opacity(0.1)
                   : (colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.2))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {

            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(tileBg)
            if isSelected {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: max(1, size * 0.035))
            }

            GeometryReader { geo in
                let pad = geo.size.width * 0.10
                let iw = geo.size.width - pad * 2
                let ih = geo.size.height - pad * 2
                let gap = max(1.0, geo.size.width * 0.04)

                ZStack(alignment: .topLeading) {
                    ForEach(0..<sections.count, id: \.self) { i in
                        let s = sections[i]
                        let x = pad + s.xPercentage * iw + gap / 2
                        let y = pad + (1.0 - s.yPercentage - s.heightPercentage) * ih + gap / 2
                        let w = max(0, s.widthPercentage * iw - gap)
                        let h = max(0, s.heightPercentage * ih - gap)

                        RoundedRectangle(cornerRadius: max(1, w * 0.08), style: .continuous)
                            .modifier {
                                if #available(macOS 14.0, *) {
                                    $0
                                        .fill(zoneFill)
                                        .stroke(zoneStroke, lineWidth: max(1, w * 0.06))
                                } else {
                                    $0.fill(zoneFill)
                                }
                            }
                            .frame(width: w, height: h)
                            .offset(x: x, y: y)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }
}

private struct DockItem: View {
    let layout: LayoutItem
    let isSelected: Bool
    let scale: CGFloat
    var isDwelling: Bool = false
    var isCompact: Bool = false

    @State private var isHovered: Bool = false
    @State private var flashOpacity: Double = 1.0

    var body: some View {
        VStack(spacing: isCompact ? 0 : 5) {
            itemIcon
            if !isCompact {
                itemLabel
            }
        }
        .opacity(isDwelling ? flashOpacity : 1.0)
        .onChange(of: isDwelling) { dwelling in
            if dwelling {
                withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true)) {
                    flashOpacity = 0.35
                }
            } else {
                withAnimation(.easeInOut(duration: 0.12)) {
                    flashOpacity = 1.0
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
            
            
        }
        .help(layout.name)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isCompact)
    }

    private var iconSize: CGFloat { isCompact ? 26 : 44 }

    private var itemIcon: some View {
        LayoutPreviewIcon(sections: layout.sections,
                          isSelected: isSelected || isHovered,
                          size: iconSize)
            .scaleEffect(scale, anchor: .bottom)
    }

    private var itemLabel: some View {
        Text(layout.name)
            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundColor(isSelected ? .primary : .secondary)
            .frame(width: 64)
    }
}

private struct LayoutSwitcherPanelView: View {
    @ObservedObject var appLayouts: UserLayouts
    @ObservedObject var mouseState: LayoutDockMouseState

    var mode: LayoutSwitcherMode = .direct
    var onHoldSelect: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            LayoutSwitcher(
                selectedLayoutName: $appLayouts.currentLayoutName,
                layouts: Array(appLayouts.layouts.values)
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    .compactMap { layout -> LayoutItem? in
                        guard layout.layoutType == .zone else { return nil }
                        let sections = Array(layout.sectionConfigs.values)
                            .sorted { ($0.number ?? 0) < ($1.number ?? 0) }
                        return LayoutItem(name: layout.name, layoutType: .zone, sections: sections)
                    },
                mouseState: mouseState,
                mode: mode,
                onHoldSelect: onHoldSelect
            )
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

class LayoutSwitcherPanel {
    private let panel: NSPanel
    private let mouseState = LayoutDockMouseState()
    private var pollingTimer: Timer?
    private var isShown = false
    private var mode: LayoutSwitcherMode = .direct
    
    private var isSuppressed = false

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar + 2
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.alphaValue = 0
        panel.hasShadow = false
    }

    func switchLayout(to name: String) {
        isSwitcherUsed = true

        let isSameLayout = (name == userLayouts.currentLayoutName)

        guard !isSameLayout || mode == .actual else { return }

        isSuppressed = true

        let old = userLayouts.currentLayout
        
        if !isSameLayout {
            old.layoutWindow.hide()
            userLayouts.currentLayoutName = name
        }

        let new = userLayouts.currentLayout

        stopEditing()

        userLayouts.selectLayout(userLayouts.currentLayoutName)

        setIsFitting(true)
        new.layoutWindow.show()

        if appSettings.selectPerDesktopLayout {
            spaceLayoutPreferences.setCurrent(layoutName: userLayouts.currentLayoutName)
            spaceLayoutPreferences.save()
        }

        isSuppressed = false

        if let screen = getFocusedScreen() {
            show(on: screen)
        }
    }

    private func rebuildContent(mode: LayoutSwitcherMode, frame: NSRect) {
        let onHold: ((String) -> Void)?

        switch mode {
            case .direct:
                onHold = { [weak self] name in
                    guard NSEvent.pressedMouseButtons & 1 != 0 else { return }
                    self?.switchLayout(to: name)
                }
            case .actual:
                onHold = { [weak self] name in
                    guard NSEvent.pressedMouseButtons & 1 != 0, let self else { return }
                    self.switchLayout(to: name)
                }
        }
        
        panel.contentView = NSHostingView(rootView: LayoutSwitcherPanelView(
            appLayouts: userLayouts,
            mouseState: mouseState,
            mode: mode,
            onHoldSelect: onHold
        ))
    }

    private func computeFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame
        let panelHeight: CGFloat = 110
        let itemCount = max(userLayouts.layouts.count, 1)
        let panelWidth = min(screenFrame.width - 40, CGFloat(itemCount) * 74 + 48)
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - panelHeight - 8

        return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }
    
    func show(on screen: NSScreen) {
        guard !isSuppressed else { return }

        let frame = computeFrame(for: screen)

        mode = .direct
        mouseState.isExpanded = true
        mouseState.hostWindowFrame = frame

        rebuildContent(mode: .direct, frame: frame)

        panel.setFrame(frame, display: true, animate: false)

        if !isShown {
            panel.alphaValue = 0
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                self.panel.animator().alphaValue = 1
            }

            isShown = true
        } else {
            panel.orderFrontRegardless()
        }

        startPollingTimer()
    }
    
    func showActualMode(on screen: NSScreen) {
        guard !isSuppressed, !isShown else { return }
        
        let frame = computeFrame(for: screen)

        mode = .actual
        mouseState.isExpanded = false  
        mouseState.hostWindowFrame = frame

        rebuildContent(mode: .actual, frame: frame)

        panel.setFrame(frame, display: true, animate: false)

        panel.alphaValue = 0

        panel.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            self.panel.animator().alphaValue = 1
        }

        startPollingTimer()

        isShown = true
    }

    private func startPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            let loc = NSEvent.mouseLocation
            self.mouseState.position = loc
            
            if self.mode == .actual {
                let isOver = self.panel.frame.contains(loc)
                if self.mouseState.isExpanded != isOver {
                    withAnimation(.bouncy(duration: 0.25)) {
                        self.mouseState.isExpanded = isOver
                    }
                }
            }
        }
    }

    func move(to screen: NSScreen) {
        guard isShown, !isSuppressed else { return }

        let frame = computeFrame(for: screen)

        mouseState.hostWindowFrame = frame
        panel.setFrame(frame, display: true, animate: false)
        panel.orderFrontRegardless()
    }

    func hide() {
        guard isShown, !isSuppressed else { return }

        isSwitcherUsed = false

        isShown = false
        mode = .direct
        pollingTimer?.invalidate()
        pollingTimer = nil
        mouseState.position = CGPoint(x: -10_000, y: -10_000)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            self.panel.animator().alphaValue = 0
        }, completionHandler: {
            self.panel.orderOut(nil)
            self.mouseState.isExpanded = true
        })
    }
}

#Preview {
    LayoutSwitcher(
        selectedLayoutName: .constant("Split Screen"),
        layouts: [
            LayoutItem(name: "Split Screen", layoutType: .zone),
            LayoutItem(name: "Productivity", layoutType: .zone),
            LayoutItem(name: "Quarters", layoutType: .zone),
        ]
    )
    .padding()
    .frame(width: 600)
}


