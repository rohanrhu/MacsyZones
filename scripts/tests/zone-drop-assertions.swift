var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
    checks += 1
}

let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)

func zone(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
          anchorX: CGFloat? = nil, anchorY: CGFloat? = nil) -> ZoneDropCandidate {
    let frame = CGRect(x: screen.width * x, y: screen.height * y,
                       width: screen.width * width, height: screen.height * height)
    return ZoneDropCandidate(frame: frame,
                             anchor: zoneDropAnchor(in: frame, anchorXPercentage: anchorX, anchorYPercentage: anchorY))
}

func select(_ candidates: [ZoneDropCandidate], at point: CGPoint,
            strategy: SnapHighlightStrategy = .centerProximity, prioritizeAnchor: Bool = false) -> Int? {
    selectZoneDropCandidate(candidates, mouseLocation: point, strategy: strategy, prioritizeAnchor: prioritizeAnchor)
}

// Anchor geometry
let frame = CGRect(x: 100, y: 200, width: 400, height: 300)
expect(zoneDropAnchor(in: frame, anchorXPercentage: nil, anchorYPercentage: nil) == CGPoint(x: 300, y: 350),
       "missing anchor falls back to the zone center")
expect(zoneDropAnchor(in: frame, anchorXPercentage: 0.25, anchorYPercentage: 0.75) == CGPoint(x: 200, y: 425),
       "anchor is relative to the zone, measured from its bottom-left corner")
expect(zoneDropAnchor(in: frame, anchorXPercentage: 0.25, anchorYPercentage: nil) == CGPoint(x: 300, y: 350),
       "a half-set anchor falls back to the zone center")

// Issue #118: concentric zones without anchors cannot be told apart
let concentricWithoutAnchors = [zone(0, 0, 1, 1), zone(0.1, 0.1, 0.8, 0.8), zone(0.25, 0.25, 0.5, 0.5)]
for point in [CGPoint(x: 500, y: 700), CGPoint(x: 500, y: 500), CGPoint(x: 500, y: 300)] {
    expect(select(concentricWithoutAnchors, at: point) == 0, "without anchors the first tied zone always wins (#118)")
}

// Issue #118: anchors make every concentric zone reachable
let concentricWithAnchors = [
    zone(0, 0, 1, 1),                                        // Full, anchor at center
    zone(0.1, 0.1, 0.8, 0.8, anchorX: 0.5, anchorY: 0.25),   // 80%, anchor in the lower middle
    zone(0.25, 0.25, 0.5, 0.5, anchorX: 0.5, anchorY: 0.9)   // 50%, anchor in the upper middle
]
expect(select(concentricWithAnchors, at: CGPoint(x: 500, y: 700)) == 2, "upper middle selects the 50% zone")
expect(select(concentricWithAnchors, at: CGPoint(x: 500, y: 500)) == 0, "middle selects the Full zone")
expect(select(concentricWithAnchors, at: CGPoint(x: 500, y: 300)) == 1, "lower middle selects the 80% zone")

// The pointer must still be inside the zone
let leftHalfWithFarAnchor = zone(0, 0, 0.5, 1, anchorX: 1, anchorY: 0.5)
let rightHalf = zone(0.5, 0, 0.5, 1)
expect(select([leftHalfWithFarAnchor, rightHalf], at: CGPoint(x: 520, y: 500)) == 1,
       "a closer anchor does not select a zone that does not contain the pointer")
expect(select([leftHalfWithFarAnchor, rightHalf], at: CGPoint(x: 480, y: 500)) == 0,
       "the zone containing the pointer with the closest anchor wins")
expect(select([zone(0.25, 0.25, 0.5, 0.5)], at: CGPoint(x: 100, y: 100)) == nil,
       "no zone is selected outside every zone")
expect(select([], at: CGPoint(x: 500, y: 500)) == nil, "no zone is selected in an empty layout")

// Flat strategy keeps selecting the smallest containing zone
let full = zone(0, 0, 1, 1)
let quarter = zone(0, 0, 0.5, 0.5)
let centered = zone(0.25, 0.25, 0.5, 0.5, anchorX: 0.9, anchorY: 0.9)
expect(select([full, centered, quarter], at: CGPoint(x: 400, y: 400), strategy: .flat) == 1,
       "flat strategy picks the first of equally small containing zones")
expect(select([full, quarter], at: CGPoint(x: 400, y: 400), strategy: .flat) == 1,
       "flat strategy picks the smallest containing zone")

// "Prioritize center" box follows the anchor
expect(select([full, quarter, centered], at: CGPoint(x: 690, y: 690), strategy: .flat, prioritizeAnchor: true) == 2,
       "flat strategy with priority selects the zone whose anchor box contains the pointer")
expect(select([full, quarter, centered], at: CGPoint(x: 400, y: 400), strategy: .flat, prioritizeAnchor: true) == 1,
       "flat strategy with priority falls back to the smallest zone away from any anchor box")
let leftHalfWithEdgeAnchor = zone(0, 0, 0.5, 1, anchorX: 1, anchorY: 0.5)
expect(select([leftHalfWithEdgeAnchor, rightHalf], at: CGPoint(x: 530, y: 500), strategy: .flat, prioritizeAnchor: true) == 1,
       "priority box does not select a zone that does not contain the pointer")
let topRightWithNearbyAnchor = zone(0.5, 0.5, 0.5, 0.5, anchorX: 0.44, anchorY: 0.44)
expect(select([centered, topRightWithNearbyAnchor], at: CGPoint(x: 730, y: 730), strategy: .flat, prioritizeAnchor: true) == 0,
       "flat strategy with priority takes the first zone whose anchor box contains the pointer")
expect(select([centered, topRightWithNearbyAnchor], at: CGPoint(x: 730, y: 730), strategy: .centerProximity, prioritizeAnchor: true) == 1,
       "priority box is ignored by the center proximity strategy")

print("PASS: \(checks) zone drop selection checks")
