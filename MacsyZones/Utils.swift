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

func debugLog(_ message: String, file: String = #file, line: Int = #line) {
    print("[\(URL(fileURLWithPath: file).lastPathComponent):\(line)] \(message)")
}

public extension View {
  func modifier<ModifiedContent: View>(@ViewBuilder content: (_ content: Self) -> ModifiedContent
  ) -> ModifiedContent {
    content(self)
  }
}
