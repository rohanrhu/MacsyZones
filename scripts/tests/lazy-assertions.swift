var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
    checks += 1
}

let zones = (0..<20).map { UserLayout(name: "zone-\($0)", sectionConfigs: [.init(number: nil, name: "A"), .init(number: nil, name: "B")]) }
let grids = (0..<20).map { UserLayout(name: "grid-\($0)", gridConfig: .init(rows: 3, columns: 4)) }
expect(LayoutWindow.allocations == 0 && GridLayoutWindow.allocations == 0, "40 cold layouts allocate no window graphs")
for layout in zones + grids {
    expect(layout.materializedLayoutWindow == nil && layout.materializedGridLayoutWindow == nil, "nonmaterializing inspection stays cold")
    layout.hide()
    layout.hideAllWindows()
    userLayouts.currentLayout = layout
    isFitting = true; isEditing = true
    stopEditing()
    expect(!isFitting && !isEditing, "stopEditing resets editing state")
    isFitting = true; isEditing = true
    expect(toggleEditing() == false && !isFitting, "toggleEditing stop branch resets state")
}
expect(LayoutWindow.allocations == 0 && GridLayoutWindow.allocations == 0, "hide and stop-editing operations never materialize cold graphs")

let zone = zones[0]
zone.name = "renamed while cold"
zone.sectionConfigs[1]?.name = "changed while cold"
expect(LayoutWindow.allocations == 0, "configuration mutation remains cold")
zone.show()
let graph = zone.layoutWindow
expect(LayoutWindow.allocations == 1 && GridLayoutWindow.allocations == 0, "first zone show allocates exactly one zone graph")
expect(graph.name == zone.name && graph.sectionConfigs[1]?.name == "changed while cold", "first graph uses latest cold configuration")
expect(graph.sectionWindows.count == 2 && graph.showCalls == 1, "show forwards to materialized zone")
zone.hideAllWindows()
expect(!graph.isShown, "hideAllWindows clears isShown")
expect(graph.sectionWindows.allSatisfy { !$0.isHovered && $0.window.orderOutCalls == 1 && $0.editorWindow.orderOutCalls == 1 }, "hideAllWindows clears hover and hides section/editor windows")
expect(graph.window.orderOutCalls == 1 && graph.sectionResizers.allSatisfy { $0.orderOutCalls == 1 }, "hideAllWindows hides parent/resizers")
zone.show(); zone.hide()
expect(zone.layoutWindow === graph && LayoutWindow.allocations == 1, "repeat zone show/hide reuses graph")
expect(graph.hideCalls == 1 && graph.showCalls == 2, "show/hide delegation remains functional")
zone.sectionConfigs[1]?.name = "changed while warm"
expect(graph.sectionConfigs[1]?.name == "changed while warm" && graph.sectionWindows.first { $0.number == 1 }?.sectionConfig.name == "changed while warm", "warm config changes propagate to graph and section")
userLayouts.currentLayout = zone
startEditing(); stopEditing()
expect(graph.startEditingCalls == 1 && graph.stopEditingCalls == 1 && LayoutWindow.allocations == 1, "editing reuses existing zone graph")
expect(zone.gridLayoutWindow == nil && GridLayoutWindow.allocations == 0, "zone grid accessor does not create grid graph")

let grid = grids[0]
grid.name = "grid renamed while cold"
grid.gridConfig = .init(rows: 5, columns: 6)
grid.show()
let gridGraph = grid.gridLayoutWindow!
expect(GridLayoutWindow.allocations == 1 && LayoutWindow.allocations == 1, "first grid show allocates grid only")
expect(gridGraph.name == grid.name && gridGraph.gridConfig.rows == 5 && gridGraph.gridConfig.columns == 6, "grid graph uses latest cold settings")
grid.hide(); grid.hideAllWindows(); grid.show()
expect(grid.gridLayoutWindow === gridGraph && GridLayoutWindow.allocations == 1, "repeat grid show/hide reuses graph")
expect(gridGraph.showCalls == 2 && gridGraph.hideCalls == 2, "grid show and both hide APIs delegate")
expect(zones.dropFirst().allSatisfy { $0.materializedLayoutWindow == nil } && grids.dropFirst().allSatisfy { $0.materializedGridLayoutWindow == nil }, "interacting with selected layouts leaves 38 unrelated layouts cold")
print("PASS: \(checks) assertions against actual UserLayout/startEditing/stopEditing/toggleEditing source; no AppKit or application launch")
