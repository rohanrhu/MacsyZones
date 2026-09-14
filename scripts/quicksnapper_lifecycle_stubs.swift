// Test-only collaborators; production methods are appended verbatim by the runner.
// Standard library only: never import AppKit or create a real application.
final class QuickSnapperItem {
    let windowId: UInt32?
    let element: Int?
    init(_ id: UInt32) { windowId = id; element = Int(id) }
}
struct QuickSnapperView {
    let model: QuickSnapper
    let windows: [QuickSnapperItem]
}
final class NSHostingView {
    let rootView: QuickSnapperView
    init(rootView: QuickSnapperView) { self.rootView = rootView }
}
final class QuickSnapperPanel {
    var contentView: NSHostingView?
    var alphaValue: Double = 0
    var makeKeyCalls = 0
    var orderFrontCalls = 0
    var orderOutCalls = 0
    var centerCalls = 0
    func makeKey() { makeKeyCalls += 1 }
    func orderFront(_ sender: Any?) { orderFrontCalls += 1 }
    func orderOut(_ sender: Any?) { orderOutCalls += 1 }
    func animator() -> QuickSnapperPanel { self }
}
final class FakeApplication {
    var activations = 0
    func activate(ignoringOtherApps: Bool) { activations += 1 }
}
let NSApp = FakeApplication()
func centerWindowOnFocusedScreen(_ panel: QuickSnapperPanel) { panel.centerCalls += 1 }
final class NSAnimationContext {
    var duration: Double = 0
    static var completions: [() -> Void] = []
    static func runAnimationGroup(_ changes: (NSAnimationContext) -> Void, completionHandler: @escaping () -> Void) {
        changes(NSAnimationContext())
        completions.append(completionHandler)
    }
    static func completeNext() { completions.removeFirst()() }
    static func completeAll() {
        while !completions.isEmpty { completeNext() }
    }
}
struct FakeDeadline {
    static func now() -> Self { Self() }
    static func + (lhs: Self, rhs: FakeInterval) -> Self { lhs }
}
struct FakeInterval { static func milliseconds(_ value: Int) -> Self { Self() } }
final class DispatchQueue {
    static let main = DispatchQueue()
    var pending: [() -> Void] = []
    func asyncAfter(deadline: FakeDeadline, execute: @escaping () -> Void) { pending.append(execute) }
    func completeAll() {
        while !pending.isEmpty { pending.removeFirst()() }
    }
}
final class FakeSettings { var selectPerDesktopLayout = false }
let appSettings = FakeSettings()
final class FakePreferences {
    var preferredName: String?
    func getCurrent() -> String? { preferredName }
    func setCurrent(layoutName: String) { preferredName = layoutName }
}
let spaceLayoutPreferences = FakePreferences()
enum LayoutType: Equatable { case zone, grid }
final class FakeLayout {
    var layoutType: LayoutType
    var showCalls = 0
    var hideCalls = 0
    init(layoutType: LayoutType = .zone) { self.layoutType = layoutType }
    func show() { showCalls += 1 }
    func hide() { hideCalls += 1 }
    func hideAllWindows() { hideCalls += 1 }
}
final class FakeLayouts {
    var sharedLayout = FakeLayout()
    var currentLayoutName = "Default"
    var layouts: [String: FakeLayout] = [
        "Default": FakeLayout(),
        "Second": FakeLayout(),
        "GridOnly": FakeLayout(layoutType: .grid)
    ]
    var currentLayout: FakeLayout {
        layouts[currentLayoutName] ?? sharedLayout
    }
}
let userLayouts = FakeLayouts()
var isQuickSnapping = false
var isFitting = false
var toLeaveElement: Int?
var toLeaveSectionWindow: Int?
func setIsFitting(_ value: Bool) { isFitting = value }
var snapped: [(Int, UInt32)] = []
func quickSnap(sectionNumber: Int, element: Int, windowId: UInt32) { snapped.append((sectionNumber, windowId)) }
func debugLog(_ message: String) {}

// Synthetic holder: only stored fields, collaborator setup, and test adapters.
// All behavior under test comes from QuickSnapper.swift in the runner.
final class QuickSnapper {
    var isOpen = false
    let panel = QuickSnapperPanel()
    private var windows: [QuickSnapperItem] = []
    private var lifecycleGeneration = 0
    var selectedIndex = 0
    var registered = false
    var preloadItems = [QuickSnapperItem(10), QuickSnapperItem(20), QuickSnapperItem(30)]
    func registerHotkeys() { registered = true }
    func unregisterHotkeys() { registered = false }
    func loadVisibleWindows() { setWindows(preloadItems) }
