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
import AppKit
import CoreGraphics
import os

/// A permission capability MacsyZones depends on.
enum PermissionCapability: String, CaseIterable, Sendable {
    /// Controlling windows of other apps (reading/writing `kAXPositionAttribute` / `kAXSizeAttribute`).
    case windowControl
    /// Listening to global keyboard events (`keyDown` / `flagsChanged` monitors).
    case inputMonitoring
    /// Posting synthetic input events. Not used today, so it stays `notRequired`.
    case eventPosting
}

/// Three-state permission result, plus `notRequired` for capabilities we do not use.
enum PermissionStatus: String, Codable, Sendable {
    /// The system allows it and a probe proved it works.
    case granted
    /// The system explicitly refuses it (`kAXErrorAPIDisabled` / preflight false).
    case denied
    /// It cannot be decided: odd AX errors, a missing target, or a timeout.
    case unknown
    /// Not needed by this app.
    case notRequired
}

/// One probe result.
struct PermissionProbe: Codable, Sendable {
    /// "frontmost" | "finder" | "api" | "preflight"
    let id: String
    /// Bundle identifier of the target, or "system".
    let target: String
    /// Raw `AXError` value; `nil` for non-AX probes.
    let axError: Int?
    let status: PermissionStatus
    /// How long the probe took, in milliseconds.
    let latencyMs: Int
}

/// Current state of one capability.
struct CapabilityState: Sendable {
    let capability: PermissionCapability
    var status: PermissionStatus
    var lastCheckedAt: Date
    var lastChangedAt: Date
    /// "launch" | "activate" | "wake" | "ax-failure" | "manual" | "poll"
    var trigger: String
    var probes: [PermissionProbe]
    /// Non-nil whenever `status` is `unknown`.
    var lastError: String?
    /// End of the post-login grace window (`nil` when not in a suspect state).
    var suspectUntil: Date?
}

/// One complete evaluation of every capability.
struct PermissionSnapshot: Sendable {
    let generatedAt: Date
    let capabilities: [CapabilityState]
    /// The window-control status; this is what the rest of the app gates on.
    let overall: PermissionStatus
}

/// Pure decision helpers, kept free of AppKit so they stay easy to reason about.
enum PermissionRules {
    /// macOS reports a freshly granted permission as denied for a short while right
    /// after login (tccd is still busy with every other login item). Anything inside
    /// this window is treated as "suspect" instead of "denied".
    static let graceWindowSeconds: TimeInterval = 60.0

    /// Any probe that works wins; all probes refusing means denied; everything else is unknown.
    static func summarizeWindowControl(frontmost: PermissionStatus, finder: PermissionStatus) -> PermissionStatus {
        if frontmost == .granted { return .granted }
        if finder == .granted { return .granted }
        if frontmost == .denied && finder == .denied { return .denied }
        return .unknown
    }

    /// Maps a raw `AXError` value onto the three-state model.
    @inlinable
    static func status(forAXError axError: Int) -> PermissionStatus {
        switch axError {
        case 0: return .granted
        case Int(AXError.apiDisabled.rawValue): return .denied
        default: return .unknown
        }
    }

    /// Grace only applies to the first minute after launch: a permission revoked while
    /// the app is running is a deliberate user action and takes effect immediately.
    static func shouldEnterGrace(previous: PermissionStatus, probe: PermissionStatus, secondsSinceLaunch: TimeInterval) -> Bool {
        previous == .granted && probe == .denied && secondsSinceLaunch < graceWindowSeconds
    }
}

/// Tracks the permissions MacsyZones needs and re-evaluates them on meaningful events.
///
/// Why this exists: since macOS 27 a single `AXIsProcessTrustedWithOptions` call is no
/// longer a reliable answer. The Accessibility setting was split into “System & App
/// Protection Override” and “Accessibility”, permissions are recorded per target app
/// and per executable, and the system does not let an app prompt on its own anymore.
/// A probe that actually touches another app’s windows is the only way to know.
@MainActor
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    /// Most recent evaluation; `nil` until the first batch finishes.
    @Published private(set) var snapshot: PermissionSnapshot?

    /// `false` until the first full evaluation has been published. Every “show the
    /// guidance only when denied” decision must wait for it, otherwise an already
    /// authorized user sees the dialog for a frame on every launch.
    @Published private(set) var hasCompletedFirstCheck = false

    /// Called on the main thread whenever a capability actually changes state.
    var onStatusChange: ((PermissionCapability, PermissionStatus, PermissionStatus) -> Void)?

    private let probeQueue = DispatchQueue(label: "MeowingCat.MacsyZones.permissions.probe", qos: .utility)
    private let launchedAt = Date()
    private let log = Logger(subsystem: "MeowingCat.MacsyZones", category: "permissions")

    private var capabilities: [PermissionCapability: CapabilityState] = [:]
    private var pollWorkItem: DispatchWorkItem?
    private var graceWorkItem: DispatchWorkItem?
    private var pollCount = 0
    private var lastTriggerAt: [String: Date] = [:]
    private var batchInFlight = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultCenterObservers: [NSObjectProtocol] = []

    private init() {}

    // MARK: - Lifecycle

    /// Starts observing system events and runs the first evaluation.
    func start() {
        registerSystemTriggers()
        recheck(trigger: "launch")
    }

    /// Stops timers and removes observers. Safe to call more than once.
    func stop() {
        cancelTimers()
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()
        for token in defaultCenterObservers {
            NotificationCenter.default.removeObserver(token)
        }
        defaultCenterObservers.removeAll()
    }

    func status(of capability: PermissionCapability) -> PermissionStatus? {
        capabilities[capability]?.status
    }

    private func cancelTimers() {
        pollWorkItem?.cancel()
        pollWorkItem = nil
        graceWorkItem?.cancel()
        graceWorkItem = nil
    }

    /// `NSApplication.didBecomeActiveNotification` never fires for an app running with
    /// `.prohibited` activation policy, so AppKit activation is not used here.
    private func registerSystemTriggers() {
        guard workspaceObservers.isEmpty && defaultCenterObservers.isEmpty else { return }

        let activate = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recheck(trigger: "activate") }
        }
        workspaceObservers.append(activate)

        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recheck(trigger: "wake") }
        }
        workspaceObservers.append(wake)

        let key = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recheck(trigger: "activate") }
        }
        defaultCenterObservers.append(key)
    }

    // MARK: - Evaluation entry points

    /// Re-evaluates every capability. Repeated calls with the same trigger within a
    /// second are coalesced, and a request arriving during a running batch is dropped.
    func recheck(trigger: String) {
        let now = Date()
        if let last = lastTriggerAt[trigger], now.timeIntervalSince(last) < 1.0 { return }
        lastTriggerAt[trigger] = now
        guard !batchInFlight else { return }

        if trigger != "poll" { pollCount = 0 }

        batchInFlight = true
        runProbeBatch(trigger: trigger)
    }

    /// Called by the window observer when an AX call fails: a disabled API is a strong
    /// hint that the permission was revoked, so re-check immediately.
    func reportAXFailure(_ error: AXError) {
        guard error == .apiDisabled else { return }
        recheck(trigger: "ax-failure")
    }

    // MARK: - Probes

    private func runProbeBatch(trigger: String) {
        probeQueue.async { [weak self] in
            let probes = [
                Self.frontmostProbe(),
                Self.finderProbe(),
                Self.apiProbe(),
                Self.preflightProbe(),
            ]
            Task { @MainActor in
                self?.finishBatch(trigger: trigger, probes: probes)
            }
        }
    }

    /// Runs one possibly blocking AX read off the main thread and waits at most `timeout`.
    private nonisolated static func guardedProbe(
        id: String,
        target: String,
        timeout: TimeInterval = 1.0,
        work: @escaping () -> Int
    ) -> PermissionProbe {
        let startedAt = DispatchTime.now()
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var axError: Int?
        DispatchQueue.global(qos: .utility).async {
            let result = work()
            lock.lock()
            if axError == nil { axError = result }
            lock.unlock()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        let latencyMs = Int(Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000.0)
        lock.lock()
        let outcome = axError
        lock.unlock()

        guard let outcome else {
            return PermissionProbe(id: id, target: target, axError: nil, status: .unknown, latencyMs: latencyMs)
        }
        return PermissionProbe(id: id, target: target, axError: outcome, status: PermissionRules.status(forAXError: outcome), latencyMs: latencyMs)
    }

    /// Reads the window list of the frontmost app. Read-only, no side effects.
    private nonisolated static func frontmostProbe() -> PermissionProbe {
        let app = NSWorkspace.shared.frontmostApplication
        let target = app?.bundleIdentifier ?? "system"
        guard let pid = app?.processIdentifier, pid > 0 else {
            return PermissionProbe(id: "frontmost", target: target, axError: nil, status: .unknown, latencyMs: 0)
        }
        let element = AXUIElementCreateApplication(pid)
        return guardedProbe(id: "frontmost", target: target) {
            var value: CFTypeRef?
            return Int(AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value).rawValue)
        }
    }

    /// Finder runs almost always and is unaffected by the WebKit side of the macOS 27
    /// known-issue list, so it makes a good second opinion.
    private nonisolated static func finderProbe() -> PermissionProbe {
        let finder = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }
        let target = "com.apple.finder"
        guard let pid = finder?.processIdentifier, pid > 0 else {
            return PermissionProbe(id: "finder", target: target, axError: nil, status: .unknown, latencyMs: 0)
        }
        let element = AXUIElementCreateApplication(pid)
        return guardedProbe(id: "finder", target: target) {
            var value: CFTypeRef?
            return Int(AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value).rawValue)
        }
    }

    /// `AXIsProcessTrusted()` is logged for diagnostics only: apps have reported it
    /// returning false while everything actually worked, and the other way around.
    private nonisolated static func apiProbe() -> PermissionProbe {
        let startedAt = DispatchTime.now()
        let trusted = AXIsProcessTrusted()
        let latencyMs = Int(Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000.0)
        return PermissionProbe(id: "api", target: "system", axError: nil, status: trusted ? .granted : .denied, latencyMs: latencyMs)
    }

    /// `CGPreflightListenEventAccess()` answers the input-monitoring question directly.
    private nonisolated static func preflightProbe() -> PermissionProbe {
        let startedAt = DispatchTime.now()
        let allowed = CGPreflightListenEventAccess()
        let latencyMs = Int(Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000.0)
        return PermissionProbe(id: "preflight", target: "system", axError: nil, status: allowed ? .granted : .denied, latencyMs: latencyMs)
    }

    // MARK: - State machine

    private func finishBatch(trigger: String, probes: [PermissionProbe]) {
        batchInFlight = false

        for probe in probes {
            log.info("probe=\(probe.id, privacy: .public) target=\(probe.target, privacy: .public) status=\(probe.status.rawValue, privacy: .public) axError=\(probe.axError.map(String.init) ?? "none", privacy: .public) latencyMs=\(probe.latencyMs, privacy: .public)")
        }

        let frontmost = probes.first { $0.id == "frontmost" }
        let finder = probes.first { $0.id == "finder" }
        let preflight = probes.first { $0.id == "preflight" }

        let windowControlProbeStatus = PermissionRules.summarizeWindowControl(
            frontmost: frontmost?.status ?? .unknown,
            finder: finder?.status ?? .unknown
        )

        var newStates: [PermissionCapability: CapabilityState] = [:]
        let now = Date()
        let secondsSinceLaunch = now.timeIntervalSince(launchedAt)

        newStates[.windowControl] = applyStateMachine(
            capability: .windowControl,
            probeStatus: windowControlProbeStatus,
            probes: [frontmost, finder].compactMap { $0 },
            trigger: trigger,
            now: now,
            secondsSinceLaunch: secondsSinceLaunch
        )
        newStates[.inputMonitoring] = applyStateMachine(
            capability: .inputMonitoring,
            probeStatus: preflight?.status ?? .unknown,
            probes: [preflight].compactMap { $0 },
            trigger: trigger,
            now: now,
            secondsSinceLaunch: secondsSinceLaunch
        )
        newStates[.eventPosting] = CapabilityState(
            capability: .eventPosting,
            status: .notRequired,
            lastCheckedAt: now,
            lastChangedAt: capabilities[.eventPosting]?.lastChangedAt ?? now,
            trigger: trigger,
            probes: [],
            lastError: nil,
            suspectUntil: nil
        )

        commitState(newStates, now: now)
    }

    private func applyStateMachine(
        capability: PermissionCapability,
        probeStatus: PermissionStatus,
        probes: [PermissionProbe],
        trigger: String,
        now: Date,
        secondsSinceLaunch: TimeInterval
    ) -> CapabilityState {
        let previous = capabilities[capability]

        // Right after login, a "denied" answer is not trustworthy yet: keep the last
        // known good state while the system is still settling (and re-check at the end
        // of the grace window).
        if let previous, PermissionRules.shouldEnterGrace(previous: previous.status, probe: probeStatus, secondsSinceLaunch: secondsSinceLaunch) {
            var state = previous
            state.lastCheckedAt = now
            state.trigger = trigger
            state.probes = probes
            state.suspectUntil = previous.suspectUntil ?? launchedAt.addingTimeInterval(PermissionRules.graceWindowSeconds)
            return state
        }

        var state = previous ?? CapabilityState(
            capability: capability,
            status: .unknown,
            lastCheckedAt: now,
            lastChangedAt: now,
            trigger: trigger,
            probes: [],
            lastError: nil,
            suspectUntil: nil
        )
        let oldStatus = state.status
        state.status = probeStatus
        state.lastCheckedAt = now
        state.trigger = trigger
        state.probes = probes
        state.suspectUntil = nil
        state.lastError = (probeStatus == .unknown)
            ? "probegroup \(probes.map { "\($0.id)=\($0.status.rawValue)" }.joined(separator: ","))"
            : nil
        if oldStatus != probeStatus {
            state.lastChangedAt = now
        }
        return state
    }

    private func commitState(_ newStates: [PermissionCapability: CapabilityState], now: Date) {
        var changed: [(PermissionCapability, PermissionStatus, PermissionStatus)] = []
        for (capability, newState) in newStates {
            let old = capabilities[capability]?.status
            if let old, old != newState.status {
                changed.append((capability, old, newState.status))
            }
            capabilities[capability] = newState
        }

        let snapshot = PermissionSnapshot(
            generatedAt: now,
            capabilities: PermissionCapability.allCases.compactMap { capabilities[$0] },
            overall: capabilities[.windowControl]?.status ?? .unknown
        )
        self.snapshot = snapshot
        if !hasCompletedFirstCheck { hasCompletedFirstCheck = true }

        for (capability, old, new) in changed {
            log.notice("capability=\(capability.rawValue, privacy: .public) status=\(new.rawValue, privacy: .public) previous=\(old.rawValue, privacy: .public)")
            onStatusChange?(capability, old, new)
        }

        log.info("probe=summary overall=\(snapshot.overall.rawValue, privacy: .public) trigger=\(newStates[.windowControl]?.trigger ?? "unknown", privacy: .public)")

        scheduleNextPoll(overall: snapshot.overall)

        // When a state is being held over the grace window, make sure the switch flips
        // exactly when the window closes instead of waiting for the next slow poll.
        if let suspectUntil = newStates.values.compactMap({ $0.suspectUntil }).min() {
            scheduleGraceRecheck(at: suspectUntil)
        }
    }

    private func scheduleNextPoll(overall: PermissionStatus) {
        cancelTimers()

        if overall == .granted {
            schedulePoll(after: 60.0)
            return
        }

        // Not granted: poll quickly for a couple of minutes, then settle on 30 seconds.
        if pollCount < 24 {
            pollCount += 1
            schedulePoll(after: 5.0)
        } else {
            schedulePoll(after: 30.0)
        }
    }

    private func schedulePoll(after interval: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.recheck(trigger: "poll") }
        }
        pollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    /// Re-checks once, when a suspect (grace) state reaches its deadline.
    private func scheduleGraceRecheck(at deadline: Date) {
        graceWorkItem?.cancel()
        let interval = max(0, deadline.timeIntervalSinceNow)
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.recheck(trigger: "manual") }
        }
        graceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }
}

// MARK: - Settings deep links

extension PermissionCenter {
    /// Opens the pane that lets the user grant window control.
    ///
    /// macOS 27.3 splits the old “Accessibility” pane into “System & App Protection
    /// Override” (apps that control other apps, which is us) and “Accessibility”
    /// (apps with an accessibility designation, which is not us). Both are reachable
    /// through the same anchor, so the link works on 27.0–27.2 as well.
    static func openWindowControlSettings() -> Bool {
        return openSettingsPane(anchor: "Privacy_Accessibility")
    }

    /// Opens the “Accessibility” pane, kept as a fallback for builds where the app is
    /// listed there (e.g. when an accessibility designation has been granted).
    static func openAccessibilitySettings() -> Bool {
        return openSettingsPane(anchor: "Privacy_AccessibilityApps")
    }

    private static func openSettingsPane(anchor: String) -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}
