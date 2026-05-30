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

struct LayoutItem: Equatable, Identifiable {
    let name: String
    let layoutType: LayoutType
    let sections: [SectionConfig]

    var id: String { name }

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

final class LayoutSwitcherViewModel: ObservableObject {
    @Published var layouts: [LayoutItem] = []
    @Published var selectedLayoutName: String = ""
    @Published var mode: LayoutSwitcherMode = .direct
    @Published var isExpanded: Bool = true
    @Published var isVisible: Bool = false
    @Published var localMouse: CGPoint? = nil
    @Published var dwellingName: String? = nil

    var onItemRectsChanged: (([String: CGRect]) -> Void)?

    var cachedItemRects: [String: CGRect] = [:]

    func itemRect(for name: String) -> CGRect? { cachedItemRects[name] }
}

private struct ItemRectsKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct LayoutSwitcher: View {
    @ObservedObject var model: LayoutSwitcherViewModel

    private static let coordinateSpace = "LayoutSwitcherSpace"

    private func magnification(for name: String) -> CGFloat {
        guard model.isExpanded, let mouse = model.localMouse else { return 1.0 }
        guard let rect = model.itemRect(for: name) else { return 1.0 }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let distance = hypot(mouse.x - center.x, mouse.y - center.y)
        let radius: CGFloat = 90
        guard distance < radius else { return 1.0 }

        let t = 1.0 - distance / radius
        return 1.0 + 0.45 * t * t
    }

    var body: some View {
        ZStack {
            panelContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(ItemRectsKey.self) { rects in
            model.cachedItemRects = rects
            model.onItemRectsChanged?(rects)
        }
    }

    private var panelContent: some View {
        content
            .modifier {
                if #available(macOS 26.0, *) {
                    $0.glassEffect()
                } else {
                    $0.background(BlurredWindowBackground(material: .hudWindow,
                                                          blendingMode: .behindWindow)
                        .cornerRadius(16))
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .fixedSize()
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.isExpanded)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.layouts)
    }

    @ViewBuilder
    private var content: some View {
        if model.layouts.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.slash")
                Text("No layouts")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        } else {
            HStack(alignment: .bottom, spacing: model.isExpanded ? 10 : 6) {
                ForEach(model.layouts) { layout in
                    let compact = !model.isExpanded
                    let scale = compact ? 1.0 : magnification(for: layout.name)
                    DockItem(
                        layout: layout,
                        isSelected: model.mode == .direct && model.selectedLayoutName == layout.name,
                        scale: scale,
                        isDwelling: model.dwellingName == layout.name,
                        isCompact: compact
                    )
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ItemRectsKey.self,
                                value: [layout.name: geometry.frame(in: .named(Self.coordinateSpace))]
                            )
                        }
                    )
                }
            }
            .padding(.horizontal, model.isExpanded ? 32 : 16)
            .padding(.vertical, model.isExpanded ? 24 : 12)
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

            GeometryReader { geometry in
                let pad = geometry.size.width * 0.10
                let iw = geometry.size.width - pad * 2
                let ih = geometry.size.height - pad * 2
                let gap = max(1.0, geometry.size.width * 0.04)

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
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
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
        .help(layout.name)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isCompact)
    }

    private var iconSize: CGFloat { isCompact ? 26 : 44 }

    private var itemIcon: some View {
        LayoutPreviewIcon(sections: layout.sections,
                          isSelected: isSelected,
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

final class LayoutSwitcherPanel {
    private let panel: NSPanel
    private let hostingView: NSHostingView<LayoutSwitcher>
    private let model = LayoutSwitcherViewModel()

    private var isShown = false
    private var mode: LayoutSwitcherMode = .direct
    private var isSuppressed = false

    private var itemRects: [String: CGRect] = [:]

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private let dwellInterval: TimeInterval = 0.5
    private var dwellTarget: String?
    private var dwellGeneration: UInt64 = 0

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
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.alphaValue = 0
        panel.hasShadow = false

        hostingView = NSHostingView(rootView: LayoutSwitcher(model: model))
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = [.intrinsicContentSize]
        }
        panel.contentView = hostingView

        model.onItemRectsChanged = { [weak self] rects in
            self?.itemRects = rects
        }
    }

    deinit {
        let g = globalMonitor
        let l = localMonitor
        if let g { NSEvent.removeMonitor(g) }
        if let l { NSEvent.removeMonitor(l) }
    }

    func switchLayout(to name: String) {
        isSwitcherUsed = true

        let isSameLayout = (name == userLayouts.currentLayoutName)
        guard !isSameLayout || mode == .actual else { return }

        isSuppressed = true
        defer { isSuppressed = false }

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

        if let screen = getFocusedScreen() {
            present(on: screen, mode: .direct)
        }
    }

    func show(on screen: NSScreen) {
        guard !isSuppressed else { return }
        present(on: screen, mode: .direct)
    }

    func showActualMode(on screen: NSScreen) {
        guard !isSuppressed, !isShown else { return }
        present(on: screen, mode: .actual)
    }

    func move(to screen: NSScreen) {
        guard isShown, !isSuppressed else { return }
        let frame = computeFrame(for: screen)
        panel.setFrame(frame, display: false, animate: false)
        panel.orderFrontRegardless()
    }

    func hide() {
        guard isShown else { return }

        isSwitcherUsed = false
        isShown = false
        mode = .direct

        stopTracking()
        cancelDwell()

        model.localMouse = nil
        model.dwellingName = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            self.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            if !self.isShown {
                self.panel.orderOut(nil)
                self.model.isVisible = false
                self.model.isExpanded = true
            }
        })
    }

    private func present(on screen: NSScreen, mode newMode: LayoutSwitcherMode) {
        mode = newMode
        refreshLayouts()

        model.mode = newMode
        model.isExpanded = (newMode == .direct)

        let frame = computeFrame(for: screen)
        panel.setFrame(frame, display: false, animate: false)

        if !isShown {
            model.isVisible = false
            model.localMouse = nil
            model.dwellingName = nil

            panel.alphaValue = 0
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                self.panel.animator().alphaValue = 1
            }

            isShown = true
            model.isVisible = true
            startTracking()
        } else {
            panel.orderFrontRegardless()
        }

        handleMouse(globalLocation: NSEvent.mouseLocation)
    }

    private func refreshLayouts() {
        let items = userLayouts.layouts.values
            .filter { $0.layoutType == .zone }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { layout -> LayoutItem in
                let sections = layout.sectionConfigs.values
                    .sorted { ($0.number ?? 0) < ($1.number ?? 0) }
                return LayoutItem(name: layout.name, layoutType: .zone, sections: Array(sections))
            }

        model.layouts = items
        model.selectedLayoutName = userLayouts.currentLayoutName
    }

    private func computeFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame

        let panelHeight: CGFloat = 150
        let itemCount = max(model.layouts.count, userLayouts.layouts.count, 1)
        let desiredWidth = CGFloat(itemCount) * 80 + 96
        let panelWidth = min(screenFrame.width - 40, max(desiredWidth, 240))

        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - panelHeight
        
        return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }

    private func contentBounds() -> CGRect? {
        let rects = itemRects.values
        guard let first = rects.first else { return nil }
        var box = first
        for r in rects.dropFirst() { box = box.union(r) }
        return box.insetBy(dx: -16, dy: -16)
    }

    private func startTracking() {
        stopTracking()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.handleMouse(globalLocation: NSEvent.mouseLocation)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouse(globalLocation: NSEvent.mouseLocation)
            return event
        }
    }

    private func stopTracking() {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
    }

    private func handleMouse(globalLocation: CGPoint) {
        guard isShown else { return }

        let frame = panel.frame

        let local = CGPoint(
            x: globalLocation.x - frame.origin.x,
            y: frame.maxY - globalLocation.y
        )

        let isInside: Bool
        if let bounds = contentBounds() {
            isInside = bounds.contains(local)
        } else {
            isInside = frame.contains(globalLocation)
        }

        if mode == .actual {
            let shouldExpand = isInside
            if model.isExpanded != shouldExpand {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    model.isExpanded = shouldExpand
                }
            }
        }

        guard isInside else {
            if model.localMouse != nil { model.localMouse = nil }
            cancelDwell()
            return
        }

        model.localMouse = local
        updateDwell(at: local)
    }

    private func itemName(at localPoint: CGPoint) -> String? {
        for layout in model.layouts {
            if let rect = itemRects[layout.name], rect.contains(localPoint) {
                return layout.name
            }
        }
        return nil
    }

    private func updateDwell(at localPoint: CGPoint) {
        guard model.isExpanded else { cancelDwell(); return }

        let target = itemName(at: localPoint)
        guard target != dwellTarget else { return }

        cancelDwell()

        dwellTarget = target

        guard let name = target else { return }

        if mode == .direct && name == userLayouts.currentLayoutName {
            model.dwellingName = nil
            return
        }

        model.dwellingName = name

        dwellGeneration &+= 1
        let generation = dwellGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + dwellInterval) { [weak self] in
            guard let self else { return }
            guard self.dwellGeneration == generation else { return }
            guard self.isShown else { return }
            guard self.dwellTarget == name else { return }
            guard NSEvent.pressedMouseButtons & 0x1 != 0 else {
                self.cancelDwell()
                return
            }

            self.model.dwellingName = nil
            self.dwellTarget = nil
            self.switchLayout(to: name)
        }
    }

    private func cancelDwell() {
        dwellGeneration &+= 1
        dwellTarget = nil
        if model.dwellingName != nil {
            model.dwellingName = nil
        }
    }
}

#Preview {
    let vm = LayoutSwitcherViewModel()

    vm.layouts = [
        LayoutItem(name: "Split Screen", layoutType: .zone),
        LayoutItem(name: "Productivity", layoutType: .zone),
        LayoutItem(name: "Quarters", layoutType: .zone),
    ]

    vm.selectedLayoutName = "Split Screen"
    vm.isVisible = true
    
    return LayoutSwitcher(model: vm)
        .padding()
        .frame(width: 600)
}
