    // Expose private production entry points to simulate already-delivered hotkeys.
    func deliverNavigation(_ offset: Int) { selectWindow(offset: offset) }
    func deliverSelection() -> QuickSnapperItem? { selectedWindowForHotkey() }
    var capturedWindowCount: Int { windows.count }
}

var quickSnapper = QuickSnapper()
var assertions = 0
func expect(_ result: @autoclosure () -> Bool, _ message: String) {
    guard result() else { fatalError("FAIL: \(message)") }
    assertions += 1
}
func freshScenario() {
    NSAnimationContext.completions.removeAll()
    DispatchQueue.main.pending.removeAll()
    quickSnapper = QuickSnapper()
    userLayouts.currentLayoutName = "Default"
    for layout in userLayouts.layouts.values {
        layout.showCalls = 0
        layout.hideCalls = 0
    }
    spaceLayoutPreferences.preferredName = nil
    appSettings.selectPerDesktopLayout = false
    NSApp.activations = 0
    isQuickSnapping = false
    isFitting = false
    snapped.removeAll()
}

// Clamping is tested through the actual public data replacement operation.
freshScenario()
quickSnapper.selectedIndex = 12
quickSnapper.setWindows([QuickSnapperItem(1), QuickSnapperItem(2)])
expect(quickSnapper.selectedIndex == 1, "replacing windows clamps excessive index")
quickSnapper.selectedIndex = -4
quickSnapper.setWindows([QuickSnapperItem(1), QuickSnapperItem(2)])
expect(quickSnapper.selectedIndex == 0, "replacing windows clamps negative index")
quickSnapper.selectedIndex = 50
quickSnapper.setWindows([])
expect(quickSnapper.selectedIndex == 0 && quickSnapper.capturedWindowCount == 0, "empty replacement resets index")

// Open but empty: late keyboard deliveries must never divide/index by zero.
quickSnapper.preloadItems = []
quickSnapper.open()
quickSnapper.deliverNavigation(1)
quickSnapper.deliverNavigation(-1)
quickSnapper.snapToZone(1)
expect(quickSnapper.selectedIndex == 0, "empty navigation is inert")
expect(quickSnapper.deliverSelection() == nil && snapped.isEmpty, "empty selection/snap hotkey is inert")

// Actual navigation wraps both directions and clamps selection before snapping.
quickSnapper.setWindows([QuickSnapperItem(1), QuickSnapperItem(2), QuickSnapperItem(3)])
quickSnapper.deliverNavigation(-1)
expect(quickSnapper.selectedIndex == 2, "previous wraps from first to last")
quickSnapper.deliverNavigation(1)
expect(quickSnapper.selectedIndex == 0, "next wraps from last to first")
for _ in 0..<30 { quickSnapper.deliverNavigation(1); quickSnapper.deliverNavigation(-1) }
expect(quickSnapper.selectedIndex == 0, "repeated navigation stays valid")
quickSnapper.selectedIndex = 900
expect(quickSnapper.deliverSelection()?.windowId == 3 && quickSnapper.selectedIndex == 2, "late selected-window hotkey clamps upper bound")
quickSnapper.selectedIndex = -900
quickSnapper.snapToZone(4)
expect(quickSnapper.selectedIndex == 0 && snapped.last?.1 == 1, "snap hotkey clamps lower bound before selecting")
quickSnapper.close()
expect(!quickSnapper.isOpen && !isQuickSnapping && !quickSnapper.registered, "close clears open state and unregisters")
expect(quickSnapper.capturedWindowCount == 0, "close immediately drops captured windows")
let selectionAfterClose = quickSnapper.selectedIndex
let snapsAfterClose = snapped.count
quickSnapper.deliverNavigation(1)
quickSnapper.deliverNavigation(-1)
quickSnapper.snapToZone(9)
expect(quickSnapper.deliverSelection() == nil && quickSnapper.selectedIndex == selectionAfterClose, "delivered hotkeys after close are inert")
expect(snapped.count == snapsAfterClose, "closed snap cannot act on a formerly selected window")
NSAnimationContext.completeAll()
expect(quickSnapper.panel.contentView == nil && quickSnapper.panel.orderOutCalls == 1, "current close completion releases hosted content and hides panel")

// Close then reopen before the old fade-out completes. The old close must not
// clear or hide the replacement hosting view installed by the new open.
freshScenario()
quickSnapper.open()
NSAnimationContext.completeAll()
DispatchQueue.main.completeAll()
quickSnapper.close()
quickSnapper.open()
let replacementContent = quickSnapper.panel.contentView
let orderOutBefore = quickSnapper.panel.orderOutCalls
NSAnimationContext.completeNext() // Explicit previous close.
expect(quickSnapper.panel.contentView === replacementContent, "stale close preserves reopened content")
expect(quickSnapper.panel.orderOutCalls == orderOutBefore, "stale close does not hide reopened panel")
NSAnimationContext.completeNext() // open() internally calls close().
expect(quickSnapper.panel.contentView === replacementContent, "open internal stale close also preserves content")
NSAnimationContext.completeAll()
expect(quickSnapper.isOpen && quickSnapper.capturedWindowCount == 3, "reopened session stays functional")

// Open then close before its callbacks fire: neither animation completion nor
// delayed layout presentation may reactivate or reveal the closed session.
freshScenario()
quickSnapper.open()
quickSnapper.close()
let activationsBefore = NSApp.activations
let keyCallsBefore = quickSnapper.panel.makeKeyCalls
let centersBefore = quickSnapper.panel.centerCalls
NSAnimationContext.completeAll()
DispatchQueue.main.completeAll()
expect(NSApp.activations == activationsBefore && quickSnapper.panel.makeKeyCalls == keyCallsBefore, "stale open animation cannot reactivate after close")
expect(quickSnapper.panel.centerCalls == centersBefore, "stale open completion cannot recenter after close")
expect(userLayouts.currentLayout.showCalls == 0, "stale delayed presentation cannot show layout after close")
expect(quickSnapper.panel.contentView == nil && !quickSnapper.isOpen, "latest close still completes cleanup")

// Two opens overlap: only the newest open may perform delayed presentation.
freshScenario()
quickSnapper.open()
quickSnapper.open()
let activeBefore = NSApp.activations
NSAnimationContext.completeAll()
DispatchQueue.main.completeAll()
expect(NSApp.activations == activeBefore + 1, "only latest open animation performs activation")
expect(userLayouts.currentLayout.showCalls == 1, "only latest open schedules visible layout")
expect(quickSnapper.panel.contentView != nil && quickSnapper.isOpen, "current open survives all stale completions")

// Current lifecycle callbacks must still act: a guard cannot simply disable UI.
freshScenario()
quickSnapper.open()
expect(quickSnapper.registered && quickSnapper.capturedWindowCount == 3, "normal open loads windows and registers hotkeys")
let centersAtOpen = quickSnapper.panel.centerCalls
NSAnimationContext.completeAll()
DispatchQueue.main.completeAll()
expect(quickSnapper.panel.centerCalls == centersAtOpen + 1 && userLayouts.currentLayout.showCalls == 1, "current open completion and delay execute")
quickSnapper.close()
NSAnimationContext.completeAll()
expect(quickSnapper.panel.contentView == nil, "normal close releases content")

// Execute queued layout-hotkey task bodies after close: stale Left/Right must
// not reveal hidden layouts or mutate the saved per-desktop preference.
// "GridOnly" sorts between "Default" and "Second" and must be skipped entirely.
freshScenario()
quickSnapper.open()
NSAnimationContext.completeAll()
DispatchQueue.main.completeAll()
quickSnapper.deliverNextLayout()
expect(userLayouts.currentLayoutName == "Second" && spaceLayoutPreferences.preferredName == "Second", "current next-layout task skips grid layouts and selects next zone layout")
quickSnapper.deliverPreviousLayout()
expect(userLayouts.currentLayoutName == "Default", "current previous-layout task skips grid layouts and wraps to previous zone layout")
quickSnapper.close()
let layoutShowsAfterClose = userLayouts.currentLayout.showCalls
let layoutHidesAfterClose = userLayouts.currentLayout.hideCalls
quickSnapper.deliverNextLayout()
quickSnapper.deliverPreviousLayout()
expect(userLayouts.currentLayout.showCalls == layoutShowsAfterClose && userLayouts.currentLayout.hideCalls == layoutHidesAfterClose, "stale Left/Right tasks cannot reveal or hide layout after close")
expect(userLayouts.currentLayoutName == "Default" && spaceLayoutPreferences.preferredName == "Default", "stale layout tasks cannot mutate selection or preferences")

print("PASS: \(assertions) QuickSnapper lifecycle assertions using extracted production methods; no AppKit or app launch")
