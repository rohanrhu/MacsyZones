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
import AVKit

struct OnboardingStateData: Codable {
    var hasCompletedOnboarding: Bool?
}

class OnboardingState: UserData, ObservableObject {
    @Published var hasCompletedOnboarding: Bool = false
    
    init() {
        super.init(name: "OnboardingState", data: "{}", fileName: "OnboardingState.json")
    }
    
    override func load() {
        super.load()
        
        let jsonData = data.data(using: .utf8)!
        
        do {
            let state = try JSONDecoder().decode(OnboardingStateData.self, from: jsonData)
            self.hasCompletedOnboarding = state.hasCompletedOnboarding ?? false
        } catch {
            debugLog("Error parsing onboarding state JSON: \(error)")
        }
    }
    
    override func save() {
        do {
            let state = OnboardingStateData(hasCompletedOnboarding: hasCompletedOnboarding)
            
            let jsonData = try JSONEncoder().encode(state)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                data = jsonString
                super.save()
            }
        } catch {
            debugLog("Error encoding onboarding state JSON: \(error)")
        }
    }
}

let onboardingState = OnboardingState()

struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let video: String
    let icon: NSImage?
}

@available(macOS 12.0, *)
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state = onboardingState
    @State private var currentPage = 0
    let window: NSWindow?
    
    init(window: NSWindow? = nil) {
        self.window = window
    }
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to MacsyZones",
            description: "**MacsyZones** is your ultimate window management companion for macOS.\n\nOrganize your workspace efficiently with **powerful snap zones**, boost your productivity with **keyboard shortcuts**, and customize layouts to match your workflow.\n\nMacsyZones has unique features that makes lives better. I'm always working to make it better. You can **buy MacsyZones** to support me. Also you can **donate** to me any amount you want.\n\nVisit [macsyzones.com](https://macsyzones.com) to buy and see how you can support me. 🥳\n\nLet's get started! 🚀",
            video: "MacsyZones Onboarding Welcome",
            icon: NSImage(named: "MenuBarIcon")
        ),
        OnboardingPage(
            title: "Snapping a Window",
            description: "Snapping windows to zones is **quick and intuitive**.\n\n**1.** Hold your **Snap Key** (default: **Shift**) while dragging a window\n**2.** Your zones will appear on the screen\n**3.** Move your window over the desired zone\n**4.** Release to snap the window into place\n\n💡 **Tip:** You can also use **Snap with right click** (enabled default) to snap windows without holding the Snap Key.",
            video: "MacsyZones Onboarding Snap",
            icon: NSImage(systemSymbolName: "rectangle.on.rectangle.angled", accessibilityDescription: nil)
        ),
        OnboardingPage(
            title: "Adding and Designing Layouts",
            description: "Create **custom layouts** tailored to your needs.\n\n**1.** Click the **pencil icon** in the menu bar to enter edit mode\n**2.** Add zones by clicking the **+ button**\n**3.** Resize and position zones by **dragging their edges**\n**4.** Create new layouts for different workflows\n\n📝 **Note:** MacsyZones remembers your **preferred layout** for each screen and workspace combination. You can select which layout you want to prefer while you are on a screen and workspace.",
            video: "MacsyZones Onboarding Layout Editor",
            icon: NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: nil)
        ),
        OnboardingPage(
            title: "Shake to Snap",
            description: "A **magical way** to snap windows with motion.\n\n**1.** Grab a window by clicking and holding its **title bar**\n**2.** Shake your mouse or trackpad **rapidly**\n**3.** Zones will appear automatically\n**4.** Move and release to snap\n\n⚡ **Tip:** Adjust **shake sensitivity** in settings to match your preference. This feature is perfect for **trackpad users**!",
            video: "MacsyZones Onboarding Shake to Snap",
            icon: NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)
        ),
        OnboardingPage(
            title: "Snap Resize",
            description: "Resize windows **precisely** using zone edges.\n\n**1.** Move your mouse pointer to somewhere center of two zones' edges meet or hold your **Modifier Key** (default: **Control**) for a moment\n**2.** Snap resizers appear between zones\n**3.** Drag a window edge close to a snap resizer\n**4.** The edge snaps to the resizer for **perfect alignment**\n\n✨ **Feature:** Enable **'Show snap resizers on hover'** in settings for instant visibility without holding the Modifier Key.",
            video: "MacsyZones Onboarding Snap Resize",
            icon: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Getting started to MacsyZones")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Step \(currentPage + 1) of \(pages.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    completeOnboarding()
                }) {
                    HStack(spacing: 6) {
                        Text("Skip")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .help("Skip onboarding")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .onAppear {
                window?.center()
            }
            
            HStack(spacing: 8) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage = index
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(nsImage: page.icon ?? NSImage())
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 20, height: 20)
                                .font(.system(size: 20, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(
                                    currentPage == index
                                    ? LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    : LinearGradient(
                                        colors: [Color.secondary.opacity(0.6), Color.secondary.opacity(0.6)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            Text(page.title)
                                .font(.system(size: 10, weight: currentPage == index ? .semibold : .regular))
                                .foregroundColor(currentPage == index ? .accentColor : .secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(currentPage == index ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    currentPage == index ? Color.accentColor.opacity(0.3) : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                        .scaleEffect(currentPage == index ? 1.0 : 0.9)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            
            OnboardingPageView(page: pages[currentPage])
                .id(currentPage)
                .padding(.vertical, 10)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            
            HStack(spacing: 12) {
                if currentPage > 0 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage -= 1
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                            Text("Previous")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(currentPage == index ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(currentPage == index ? 1.0 : 0.8)
                                .animation(.easeInOut(duration: 0.2), value: currentPage)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                
                if currentPage < pages.count - 1 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage += 1
                        }
                    }) {
                        HStack(spacing: 8) {
                            Text("Next")
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(action: {
                        completeOnboarding()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                            Text("Get Started")
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 12, x: 0, y: 6)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .padding(.vertical, 20)
        .frame(minWidth: 600, minHeight: 920)
    }
    
    private func completeOnboarding() {
        state.hasCompletedOnboarding = true
        state.save()
        dismiss()
    }
}

@available(macOS 12.0, *)
struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var player: AVPlayer?
    
    private func getVideoURL() -> URL? {
        guard !page.video.isEmpty else { return nil }
        
        if let asset = NSDataAsset(name: page.video) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(page.video)
                .appendingPathExtension("mov")
            
            if !FileManager.default.fileExists(atPath: tempURL.path) {
                try? asset.data.write(to: tempURL)
            }
            
            return tempURL
        }
        
        return nil
    }
    
    private func setupPlayer(url: URL) -> AVPlayer {
        let player = AVPlayer(url: url)
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        
        return player
    }
    
    var body: some View {
        VStack(spacing: 24) {
            if let videoURL = getVideoURL() {
                VideoPlayer(player: player)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .onAppear {
                        if player == nil {
                            player = setupPlayer(url: videoURL)
                            player?.play()
                        }
                    }
                    .onDisappear {
                        player?.pause()
                    }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.1),
                                Color.accentColor.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        VStack {
                            Image(nsImage: NSImage(named: "MenuBarIcon") ?? NSImage())
                                .resizable()
                                .renderingMode(.template)
                                .aspectRatio(1, contentMode: .fit)
                                .frame(height: 40)
                                .foregroundStyle(Color.accentColor.opacity(0.6))
                                .symbolRenderingMode(.hierarchical)
                                .padding(.bottom, 20)
                            Text("Let's learn how to use MacsyZones")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.accentColor.opacity(0.6))
                        }
                    )
                    .frame(height: 280)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
            }
            
            ScrollView {
                VStack(spacing: 12) {
                    Text(page.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Text(.init(page.description))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .lineSpacing(4)
                }
            }
        }
    }
}

@available(macOS 12.0, *)
struct OnboardingWindowView: View {
    @ObservedObject var state = onboardingState
    @State private var showOnboarding = false
    
    var body: some View {
        EmptyView()
            .onAppear {
                if !state.hasCompletedOnboarding {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showOnboarding = true
                    }
                }
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView()
            }
    }
}

@available(macOS 12.0, *)
func showOnboarding() {
    let window = NSWindow()
    window.title = "Welcome to MacsyZones"
    window.styleMask = [.titled, .closable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    
    let onboardingView = OnboardingView(window: window)
    let hostingController = NSHostingController(rootView: onboardingView)
    window.contentViewController = hostingController
    
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
}

#Preview {
    if #available(macOS 12.0, *) {
        OnboardingView(window: nil)
    }
}

