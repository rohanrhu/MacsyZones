import Foundation

// UI collaborators only. UserLayout and the editing functions are extracted
// verbatim from the checkout by check_lazy_lifecycle.sh.
enum LayoutType { case zone, grid }
struct GridConfig { var rows: Int; var columns: Int }
struct SectionConfig { var number: Int?; var name: String? }
final class FakeWindow {
    var orderOutCalls = 0
    func orderOut(_ sender: Any?) { orderOutCalls += 1 }
}
final class SectionWindow {
    var sectionConfig: SectionConfig
    var number: Int? { sectionConfig.number }
    var isHovered = true
    let window = FakeWindow()
    let editorWindow = FakeWindow()
    init(_ config: SectionConfig) { sectionConfig = config }
    func reset(sectionConfig: SectionConfig) { self.sectionConfig = sectionConfig }
}
final class LayoutWindow {
    static var allocations = 0
    var name: String
    var sectionConfigs: [Int: SectionConfig]
    var sectionWindows: [SectionWindow]
    var sectionResizers = [FakeWindow(), FakeWindow()]
    var isShown = false
    var showCalls = 0
    var hideCalls = 0
    var startEditingCalls = 0
    var stopEditingCalls = 0
    let window = FakeWindow()
    init(name: String, sectionConfigs: [SectionConfig]) {
        Self.allocations += 1
        self.name = name
        self.sectionConfigs = Dictionary(uniqueKeysWithValues: sectionConfigs.map { ($0.number!, $0) })
        self.sectionWindows = sectionConfigs.map(SectionWindow.init)
    }
    func show(showLayouts: Bool, showSnapResizers: Bool, showSwitcher: Bool) {
        showCalls += 1; isShown = true
    }
    func hide() { hideCalls += 1; isShown = false }
    func startEditing() { startEditingCalls += 1 }
    func stopEditing() { stopEditingCalls += 1 }
}
final class GridLayoutWindow {
    static var allocations = 0
    var name: String
    let gridConfig: GridConfig
    var isShown = false
    var showCalls = 0
    var hideCalls = 0
    init(name: String, gridConfig: GridConfig) {
        Self.allocations += 1
        self.name = name; self.gridConfig = gridConfig
    }
    func show() { showCalls += 1; isShown = true }
    func hide() { hideCalls += 1; isShown = false }
}
final class FakeUserLayouts { var currentLayout: UserLayout! }
let userLayouts = FakeUserLayouts()
var isFitting = false
var isEditing = false
func setIsFitting(_ value: Bool) { isFitting = value }
