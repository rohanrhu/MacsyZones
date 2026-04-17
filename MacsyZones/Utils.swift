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

import Foundation
import SwiftUI
import AppKit

func debugLog(_ message: String, file: String = #file, line: Int = #line) {
    #if DEBUG
        print("[\(URL(fileURLWithPath: file).lastPathComponent):\(line)] \(message)")
    #endif
}

// Returns a human-readable screen ratio string (e.g. "1/2", "1/3") for a given percentage value.
// Uses a 0.5% tolerance to account for floating-point rounding.
func screenRatioString(for percentage: CGFloat) -> String? {
    // Common screen ratios to check against
    let ratios: [(numerator: Int, denominator: Int)] = [
        (1, 2), (1, 3), (2, 3), (1, 4), (3, 4),
        (1, 5), (2, 5), (3, 5), (4, 5),
        (1, 6), (5, 6),
        (1, 8), (3, 8), (5, 8), (7, 8)
    ]

    let tolerance: CGFloat = 0.005

    for ratio in ratios {
        let expected = CGFloat(ratio.numerator) / CGFloat(ratio.denominator)
        if abs(percentage - expected) < tolerance {
            return "\(ratio.numerator)/\(ratio.denominator)"
        }
    }

    return nil
}

public extension View {
    func modifier<ModifiedContent: View>(@ViewBuilder content: (_ content: Self) -> ModifiedContent) -> ModifiedContent {
        content(self)
    }
}
