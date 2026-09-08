// These tests call the extracted production implementation. AppKit, SwiftUI
// bindings, actual timing/focus, and file-system persistence need separate UI QA.
var assertionCount = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertionCount += 1
    guard condition() else { fatalError("Assertion \(assertionCount): \(message)") }
}

func freshReminder() -> DonationReminder {
    DispatchQueue.main.reset()
    appSettings.automaticDonationReminders = true
    appSettings.saveCount = 0
    appSettings.savedData = nil
    macsyProLock.isPro = false
    isMovingAWindow = false
    isFitting = false
    isEditing = false
    isQuickSnapping = false
    isSnapResizing = false
    NSEvent.pressedMouseButtons = 0
    return DonationReminder()
}

func reachInterval(_ reminder: DonationReminder) {
    for _ in 0..<reminder.interval { reminder.count() }
}

func decodedSavedSettings(_ settings: AppSettings) -> AppSettingsData {
    guard let data = settings.savedData?.data(using: .utf8) else {
        fatalError("Expected an in-memory settings save")
    }
    return try! JSONDecoder().decode(AppSettingsData.self, from: data)
}

// Backward-compatible defaults and real Codable/load/save behavior.
do {
    let settings = AppSettings()
    expect(settings.automaticDonationReminders, "new installs retain enabled default")
    let legacy = try! JSONDecoder().decode(AppSettingsData.self, from: Data("{}".utf8))
    expect(legacy.automaticDonationReminders == nil, "old schema omits optional reminder key")
    settings.data = #"{"enableLayoutSwitcher":false}"#
    settings.load()
    expect(settings.automaticDonationReminders, "loading legacy settings keeps enabled default")
    expect(!settings.enableLayoutSwitcher, "loading legacy settings still loads ordinary keys")
    settings.data = #"{"automaticDonationReminders":null}"#
    settings.load()
    expect(settings.automaticDonationReminders, "null optional setting preserves default")

    settings.data = #"{"automaticDonationReminders":false}"#
    settings.load()
    expect(!settings.automaticDonationReminders, "explicit opt-out is decoded")
    settings.save()
    expect(settings.saveCount == 1, "save reaches in-memory persistence exactly once")
    expect(decodedSavedSettings(settings).automaticDonationReminders == false,
           "opt-out is encoded, not dropped")
    let reloaded = AppSettings()
    reloaded.data = settings.savedData!
    reloaded.load()
    expect(!reloaded.automaticDonationReminders, "opt-out survives settings roundtrip")
    expect(!reloaded.enableLayoutSwitcher, "other preference survives same roundtrip")
    reloaded.automaticDonationReminders = true
    reloaded.save()
    expect(decodedSavedSettings(reloaded).automaticDonationReminders == true,
           "opt-in is encoded")
    reloaded.automaticDonationReminders = false
    MainActor.assumeIsolated { reloaded.resetToDefaults() }
    expect(reloaded.automaticDonationReminders, "reset restores enabled default")
    expect(decodedSavedSettings(reloaded).automaticDonationReminders == true,
           "reset persists enabled default")
}

// Interval and pending gates must prevent duplicate queued presentations.
do {
    let reminder = freshReminder()
    for _ in 0..<(reminder.interval - 1) { reminder.count() }
    expect(DispatchQueue.main.callbacks.isEmpty, "no callback before the interval")
    reminder.count()
    expect(DispatchQueue.main.callbacks.count == 1, "interval queues one callback")
    expect(DispatchQueue.main.deadlines.first?.seconds == 2, "presentation waits two seconds")
    expect(reminder.countI == 0, "interval resets the count")
    for _ in 0..<(reminder.interval * 2) { reminder.count() }
    expect(DispatchQueue.main.callbacks.count == 1, "pending callback blocks duplicate scheduling")
    expect(reminder.countI == 0, "pending callback blocks count advancement")
    DispatchQueue.main.runNext()
    expect(reminder.panel.presentations == 1, "idle enabled callback presents once")
    expect(reminder.panel.centers == 1, "presented panel is centered")
    reminder.count()
    expect(reminder.countI == 1, "delivery releases pending gate")
    reminder.hide()
    expect(!reminder.panel.isVisible, "hide dismisses an already-visible panel")
    expect(reminder.countI == 0, "hide resets count")
    expect(reminder.intervalI == 0, "hide does not advance the reminder interval")
}

for pro in [false, true] {
    let reminder = freshReminder()
    macsyProLock.isPro = pro
    appSettings.automaticDonationReminders = pro
    reachInterval(reminder)
    expect(DispatchQueue.main.callbacks.isEmpty, pro ? "Pro users do not queue" : "opted-out users do not queue")
    expect(reminder.countI == 0, "disabled/Pro gate does not advance the count")
}

// Recheck current preferences and Pro status when a queued callback executes.
for pro in [false, true] {
    let reminder = freshReminder()
    reachInterval(reminder)
    if pro { macsyProLock.isPro = true }
    else { appSettings.automaticDonationReminders = false }
    DispatchQueue.main.runNext()
    expect(reminder.panel.presentations == 0, pro ? "upgrade cancels queued presentation" : "opt-out cancels queued presentation")
    macsyProLock.isPro = false
    appSettings.automaticDonationReminders = true
    reachInterval(reminder)
    expect(DispatchQueue.main.callbacks.count == 1, "suppressed callback releases pending gate")
}

// Every interaction guard is independently relevant at callback delivery.
let busyStates: [(String, (Bool) -> Void)] = [
    ("window move", { isMovingAWindow = $0 }),
    ("fitting", { isFitting = $0 }),
    ("editing", { isEditing = $0 }),
    ("QuickSnapper", { isQuickSnapping = $0 }),
    ("snap resize", { isSnapResizing = $0 }),
    ("primary mouse button", { NSEvent.pressedMouseButtons = $0 ? 1 : 0 })
]
for (name, setBusy) in busyStates {
    let reminder = freshReminder()
    reachInterval(reminder)
    setBusy(true)
    DispatchQueue.main.runNext()
    expect(reminder.panel.presentations == 0, "\(name) blocks presentation")
    expect(reminder.panel.centers == 0, "\(name) does not center an unshown panel")
    setBusy(false)
    reachInterval(reminder)
    expect(DispatchQueue.main.callbacks.count == 1, "\(name) suppression allows a later interval")
    DispatchQueue.main.runNext()
    expect(reminder.panel.presentations == 1, "idle presentation recovers after \(name)")
}

// An obsolete callback must neither present nor consume a newer pending one.
for cancellation in ["hide", "dismiss", "disable then re-enable"] {
    let reminder = freshReminder()
    reachInterval(reminder)
    switch cancellation {
    case "hide": reminder.hide()
    case "dismiss": reminder.dismiss()
    default:
        reminder.disableAutomaticReminders()
        expect(!appSettings.automaticDonationReminders, "disable updates preference")
        expect(appSettings.saveCount == 1, "disable saves preference once")
        expect(decodedSavedSettings(appSettings).automaticDonationReminders == false,
               "disable persists false")
        appSettings.automaticDonationReminders = true
    }
    expect(reminder.countI == 0, "\(cancellation) resets count")
    expect(reminder.panel.hides == 1, "\(cancellation) hides panel")
    reachInterval(reminder)
    expect(DispatchQueue.main.callbacks.count == 2, "\(cancellation) permits a fresh pending callback")
    DispatchQueue.main.runNext()
    expect(reminder.panel.presentations == 0, "\(cancellation) invalidates stale callback")
    reminder.count()
    expect(reminder.countI == 0, "stale callback does not consume the new pending gate")
    expect(DispatchQueue.main.callbacks.count == 1, "fresh callback remains queued")
    DispatchQueue.main.runNext()
    expect(reminder.panel.presentations == 1, "fresh callback presents after \(cancellation)")
}

do {
    let reminder = freshReminder()
    reachInterval(reminder)
    reminder.disableAutomaticReminders()
    DispatchQueue.main.runNext()
    expect(reminder.panel.presentations == 0, "disable alone invalidates queued callback")
    reachInterval(reminder)
    expect(DispatchQueue.main.callbacks.isEmpty, "disabled reminders remain unscheduled")

    let dismissed = freshReminder()
    dismissed.dismiss()
    expect(dismissed.intervalI == 1, "dismiss advances reminder interval")
    expect(dismissed.interval == INTERVALS[1], "new interval uses production schedule")
    for _ in 0..<(INTERVALS.count * 2) { dismissed.dismiss() }
    expect(dismissed.intervalI == INTERVALS.count - 1, "dismiss saturates at final interval")
    reachInterval(dismissed)
    DispatchQueue.main.runNext()
    expect(dismissed.panel.presentations == 1, "final interval remains usable")
}

print("Support-reminder production-source checks passed: \(assertionCount) assertions")
