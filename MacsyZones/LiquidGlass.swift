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

// Thanks to https://github.com/JulianWindeck/liquid-glass/blob/main/LiquidGlassBackground.swift

import SwiftUI
import AppKit

let hasLiquidGlass = NSClassFromString("NSGlassEffectView") != nil

public enum GlassVariant: Int, CaseIterable, Identifiable, Sendable {
    case v0  = 0,  v1  = 1,  v2  = 2,  v3  = 3,  v4  = 4
    case v5  = 5,  v6  = 6,  v7  = 7,  v8  = 8,  v9  = 9
    case v10 = 10, v11 = 11, v12 = 12, v13 = 13, v14 = 14
    case v15 = 15, v16 = 16, v17 = 17, v18 = 18, v19 = 19

    public var id: Int { rawValue }
}

public struct LiquidGlassView<Content: View>: NSViewRepresentable {
    private let content: Content
    private let cornerRadius: CGFloat
    private let variant: GlassVariant

    public init(variant: GlassVariant = .v11,
                cornerRadius: CGFloat = 10,
                @ViewBuilder content: () -> Content) {
        self.variant = variant
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    @inline(__always)
    private func setterSelector(for key: String, privateVariant: Bool = true) -> Selector? {
        guard !key.isEmpty else { return nil }
        
        let name: String
        
        if privateVariant {
            let cleaned = key.hasPrefix("_") ? key : "_" + key
            name = "set" + cleaned
        } else {
            let first = String(key.prefix(1)).uppercased()
            let rest = String(key.dropFirst())
            name = "set" + first + rest
        }
        
        return NSSelectorFromString(name + ":")
    }

    private typealias VariantSetterIMP = @convention(c) (AnyObject, Selector, Int) -> Void

    private func callPrivateVariantSetter(on object: AnyObject, value: Int) {
        guard
            let sel = setterSelector(for: "variant", privateVariant: true),
            let m = class_getInstanceMethod(object_getClass(object), sel)
        else {
            #if DEBUG
            print("[LiquidGlassView] Failed to find private setter for 'variant' on \(type(of: object))")
            print("  - Selector: \(String(describing: setterSelector(for: "variant", privateVariant: true)))")
            print("  - Object class: \(String(describing: object_getClass(object)))")
            print("  - macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            #endif

            return
        }
        
        let imp = method_getImplementation(m)
        let f = unsafeBitCast(imp, to: VariantSetterIMP.self)
        
        f(object, sel, value)
    }

    public func makeNSView(context: Context) -> NSView {
        if let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassType.init(frame: .zero)
            let hosting = NSHostingView(rootView: content)
            
            glass.setValue(cornerRadius, forKey: "cornerRadius")
            callPrivateVariantSetter(on: glass, value: variant.rawValue)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            glass.setValue(hosting, forKey: "contentView")

            return glass
        }

        let fallback = NSVisualEffectView()

        fallback.material = .underWindowBackground

        let hosting = NSHostingView(rootView: content)

        hosting.translatesAutoresizingMaskIntoConstraints = false
        fallback.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: fallback.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: fallback.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: fallback.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: fallback.bottomAnchor)
        ])

        return fallback
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let hosting = nsView.value(forKey: "contentView") as? NSHostingView<Content> {
            hosting.rootView = content
        }

        nsView.setValue(cornerRadius, forKey: "cornerRadius")
        callPrivateVariantSetter(on: nsView, value: variant.rawValue)
    }
}
