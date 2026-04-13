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

import Cocoa
import SwiftUI
import AppKit

struct SectionView: View {
    @ObservedObject var sectionWindow: SectionWindow
    
    var backgroundColor: Color {
        sectionWindow.isHovered ? Color.accentColor.opacity(0.1) : Color.white.opacity(0.1)
    }
    
    var borderColor: Color {
        sectionWindow.isHovered ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.4)
    }
    
    var centerCircleBckground: AnyView {
        if hasLiquidGlass {
            return AnyView(
                Circle()
                    .fill((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.1 : 0.05))
                    .background(Circle()
                    .stroke((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.6 : 0.1), lineWidth: 2))
            )
        } else {
            if #available(macOS 14.0, *) {
                return hasLiquidGlass ? AnyView(Circle()
                        .fill((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.25 : 0.05))
                        .stroke((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.6 : 0.1), lineWidth: 4))
                    : AnyView(Circle()
                        .fill((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.2 : 0.1))
                        .stroke((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.5 : 0.25), lineWidth: 4)
                        .shadow(color: (sectionWindow.isHovered ? Color.accentColor : Color.black).opacity(sectionWindow.isHovered ? 0.5 : 0.5), radius: 2, x: 0, y: 0))
            } else {
                return AnyView(
                    Circle()
                        .fill((sectionWindow.isHovered ? Color.accentColor : Color.white).opacity(sectionWindow.isHovered ? 0.1 : 0.05))
                )
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Group {
                    Text(String(sectionWindow.number))
                        .frame(width: 100, height: 100)
                        .font(.system(size: 50))
                        .foregroundColor((sectionWindow.isHovered ? Color.accentColor: Color.white).opacity(0.5))
                        .blendMode(.difference)
                }
                .fixedSize()
                .shadow(color: (sectionWindow.isHovered ? Color.accentColor: Color.black), radius: 8, x: 0, y: 0)
                .background(centerCircleBckground)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .modifier {
                if #available(macOS 14.0, *) {
                    $0
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .fill(backgroundColor)
                                .stroke(borderColor, lineWidth: 4)
                                .shadow(color: .black.opacity(sectionWindow.isHovered ? 0.2 : 0.1), radius: sectionWindow.isHovered ? 8 : 4, x: 0, y: 4)
                        )
                        .cornerRadius(26)
                } else {
                    $0
                        .background(BlurredSectionBackground(opacity: sectionWindow.isHovered ? 0.5 : 0.35))
                        .border(borderColor, width: 5)
                        .cornerRadius(26)
                }
            }
        }
    }
}

enum PositioningPreset: Hashable {
    case leftHalf, rightHalf
    case topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThirdVertical, rightThird
    case topThird, centerThirdHorizontal, bottomThird
    case center
    case fullScreen
    
    var iconName: String {
        switch self {
        case .leftHalf: return "left-half"
        case .rightHalf: return "right-half"
        case .topHalf: return "top-half"
        case .bottomHalf: return "bottom-half"
        case .topLeft: return "top-left"
        case .topRight: return "top-right"
        case .bottomLeft: return "bottom-left"
        case .bottomRight: return "bottom-right"
        case .leftThird: return "left-third"
        case .centerThirdVertical: return "center-third-vertical"
        case .rightThird: return "right-third"
        case .topThird: return "top-third"
        case .centerThirdHorizontal: return "center-third-horizontal"
        case .bottomThird: return "bottom-third"
        case .center: return "center"
        case .fullScreen: return "full-screen"
        }
    }
    
    func calculateFrame(for screenFrame: NSRect) -> NSRect {
        let x = screenFrame.origin.x
        let y = screenFrame.origin.y
        let width = screenFrame.width
        let height = screenFrame.height
        
        switch self {
        case .leftHalf:
            return NSRect(x: x, y: y, width: width / 2, height: height)
        case .rightHalf:
            return NSRect(x: x + width / 2, y: y, width: width / 2, height: height)
        case .topHalf:
            return NSRect(x: x, y: y + height / 2, width: width, height: height / 2)
        case .bottomHalf:
            return NSRect(x: x, y: y, width: width, height: height / 2)
        case .topLeft:
            return NSRect(x: x, y: y + height / 2, width: width / 2, height: height / 2)
        case .topRight:
            return NSRect(x: x + width / 2, y: y + height / 2, width: width / 2, height: height / 2)
        case .bottomLeft:
            return NSRect(x: x, y: y, width: width / 2, height: height / 2)
        case .bottomRight:
            return NSRect(x: x + width / 2, y: y, width: width / 2, height: height / 2)
        case .leftThird:
            return NSRect(x: x, y: y, width: width / 3, height: height)
        case .centerThirdVertical:
            return NSRect(x: x + width / 3, y: y, width: width / 3, height: height)
        case .rightThird:
            return NSRect(x: x + width * 2 / 3, y: y, width: width / 3, height: height)
        case .topThird:
            return NSRect(x: x, y: y + height * 2 / 3, width: width, height: height / 3)
        case .centerThirdHorizontal:
            return NSRect(x: x, y: y + height / 3, width: width, height: height / 3)
        case .bottomThird:
            return NSRect(x: x, y: y, width: width, height: height / 3)
        case .center:
            let centerWidth = width * 0.5
            let centerHeight = height * 0.5
            return NSRect(x: x + (width - centerWidth) / 2, y: y + (height - centerHeight) / 2, width: centerWidth, height: centerHeight)
        case .fullScreen:
            return screenFrame
        }
    }
}

struct PositioningButton: View {
    let preset: PositioningPreset
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            if let image = NSImage(named: preset.iconName) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(isHovered ? Color.accentColor : Color.accentColor.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct EditorSectionView: View {
    var onDelete: (() -> Void)?
    @ObservedObject var sectionWindow: SectionWindow
    var number: Int
    
    private let buttonGroups: [[PositioningPreset]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .topLeft, .topRight, .bottomLeft, .bottomRight],
        [.leftThird, .centerThirdVertical, .rightThird, .topThird, .centerThirdHorizontal, .bottomThird, .center, .fullScreen]
    ]
    
    private let baseButtonSize: CGFloat = 32
    private let baseSpacing: CGFloat = 6
    private let baseGroupSpacing: CGFloat = 12
    private let basePadding: CGFloat = 10
    private let baseRowSpacing: CGFloat = 8
    private let baseCircleSize: CGFloat = 150
    private let baseNumberFontSize: CGFloat = 50
    private let baseSizeFontSize: CGFloat = 20
    private let baseSizeTopPadding: CGFloat = 110
    private let baseButtonsTopPadding: CGFloat = 20
    
    private func scaleFactor(for size: CGSize) -> CGFloat {
        let widthScale = size.width / 320
        let heightScale = size.height / 440
        return min(min(widthScale, heightScale), 1.0)
    }
    
    private func isCompact(size: CGSize) -> Bool {
        return size.width < 320 || size.height < 440
    }
    
    private func isVeryCompact(size: CGSize) -> Bool {
        return size.width < 200 || size.height < 280
    }
    
    private func isTiny(size: CGSize) -> Bool {
        return size.width < 140 || size.height < 180
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = scaleFactor(for: size)
            let compact = isCompact(size: size)
            let veryCompact = isVeryCompact(size: size)
            let tiny = isTiny(size: size)
            
            let buttonSize = max(16, baseButtonSize * scale)
            let spacing = max(2, baseSpacing * scale)
            let groupSpacing = max(4, baseGroupSpacing * scale)
            let padding = max(4, basePadding * scale)
            let rowSpacing = max(2, baseRowSpacing * scale)
            let circleSize = max(40, baseCircleSize * scale)
            let numberFontSize = max(16, baseNumberFontSize * scale)
            let sizeFontSize = max(10, baseSizeFontSize * scale)
            let sizeTopPadding = max(20, baseSizeTopPadding * scale)
            let buttonsTopPadding = max(8, baseButtonsTopPadding * scale)
            
            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 3)
                    .background(
                        RoundedRectangle(cornerRadius: 26)
                            .fill(Color.accentColor.opacity(0.1))
                    )
                
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    
                    if !tiny {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: compact ? 1 : 2)
                                .background(
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.5))
                                )
                                .frame(width: circleSize, height: circleSize)
                            
                            Text("\(number)")
                                .font(.system(size: numberFontSize, weight: .light))
                                .foregroundColor(Color.accentColor)
                                .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: -1)
                        }
                        
                        if !veryCompact {
                            let screenWidth = sectionWindow.layoutWindow.window.frame.width
                            let screenHeight = sectionWindow.layoutWindow.window.frame.height
                            let widthPct = screenWidth > 0 ? sectionWindow.windowSize.width / screenWidth : 0
                            let heightPct = screenHeight > 0 ? sectionWindow.windowSize.height / screenHeight : 0
                            let widthRatio = screenRatioString(for: widthPct)
                            let heightRatio = screenRatioString(for: heightPct)
                            let widthLabel = widthRatio.map { "\(Int(sectionWindow.windowSize.width)) px (\($0))" } ?? "\(Int(sectionWindow.windowSize.width)) px"
                            let heightLabel = heightRatio.map { "\(Int(sectionWindow.windowSize.height)) px (\($0))" } ?? "\(Int(sectionWindow.windowSize.height)) px"
                            Text("\(widthLabel) × \(heightLabel)")
                                .font(.system(size: sizeFontSize, weight: .light))
                                .foregroundColor(Color.accentColor.opacity(0.85))
                                .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: -1)
                                .padding(.top, sizeTopPadding)
                        }
                    } else {
                        Text("\(number)")
                            .font(.system(size: max(14, numberFontSize), weight: .light))
                            .foregroundColor(Color.accentColor)
                            .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: -1)
                    }
                    
                    if !veryCompact {
                        VStack(spacing: rowSpacing) {
                            ForEach(Array(buttonGroups.enumerated()), id: \.offset) { groupIndex, group in
                                HStack(spacing: spacing) {
                                    ForEach(group, id: \.self) { preset in
                                        PositioningButton(preset: preset) {
                                            applyPositioningPreset(preset)
                                        }
                                        .frame(width: buttonSize, height: buttonSize)
                                    }
                                }
                                
                                if groupIndex < buttonGroups.count - 1 {
                                    Spacer()
                                        .frame(height: max(1, groupSpacing - rowSpacing))
                                }
                            }
                        }
                        .padding(padding)
                        .background(
                            RoundedRectangle(cornerRadius: compact ? 8 : 12)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                        .padding(.top, buttonsTopPadding)
                    }
                    
                    Spacer(minLength: 0)
                }
                
                VStack {
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            onDelete?()
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: compact ? 14 : 18, weight: .regular))
                                .foregroundColor(.white)
                                .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
                                .background(
                                    RoundedRectangle(cornerRadius: compact ? 4 : 6)
                                        .fill(Color.accentColor.opacity(0.25))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, compact ? 10 : 20)
                        .padding(.trailing, compact ? 10 : 20)
                    }
                    
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            setCursorInBackground()
        }
    }
    
    private func applyPositioningPreset(_ preset: PositioningPreset) {
        let screenFrame = sectionWindow.layoutWindow.window.frame
        
        let newFrame = preset.calculateFrame(for: screenFrame)
        
        sectionWindow.editorWindow.setFrame(newFrame, display: true, animate: true)
        sectionWindow.window.setFrame(newFrame, display: true, animate: true)
    }
    
    private func setCursorInBackground() {
        let cursorInBg = CFStringCreateWithCString(kCFAllocatorDefault, "SetsCursorInBackground", 0)
        if let cursorInBg = cursorInBg {
            _ = CGSSetConnectionProperty(_CGSDefaultConnection(), _CGSDefaultConnection(), cursorInBg, kCFBooleanTrue)
        }
    }
}

struct PositioningButton: View {
    let preset: PositioningPreset
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            if let image = NSImage(named: preset.iconName) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(isHovered ? Color.accentColor : Color.accentColor.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}