// In-memory collaborators only. Production count/hide/dismiss/disable methods
// and the complete settings schema/load/save/reset implementation are appended
// by check_support_reminders.sh; none of their logic is duplicated here.
import Foundation

class UserData {
    var data: String
    var savedData: String?
    var saveCount = 0

    init(name: String, data: String, fileName: String) {
        self.data = data
        load()
    }

    func load() {}

    func save() {
        saveCount += 1
        savedData = data
    }
}

func debugLog(_ message: String) {
    fatalError("Unexpected production settings error: \(message)")
}

final class FakeHotkey {
    func register(for shortcut: String) {}
}

final class FakeQuickSnapper {
    var toggleHotkey: FakeHotkey? = FakeHotkey()
}

let quickSnapper = FakeQuickSnapper()
let cycleForwardHotkey = FakeHotkey()
let cycleBackwardHotkey = FakeHotkey()

final class FakeProLock {
    var isPro = false
}

let macsyProLock = FakeProLock()
var isMovingAWindow = false
var isFitting = false
var isEditing = false
var isQuickSnapping = false
var isSnapResizing = false

enum NSEvent {
    static var pressedMouseButtons = 0
}

struct FakeDeadline {
    var seconds: Int
    static func now() -> Self { Self(seconds: 0) }
    static func + (lhs: Self, rhs: Int) -> Self {
        Self(seconds: lhs.seconds + rhs)
    }
}

// Deliberately shadows DispatchQueue so delayed production callbacks can be
// delivered in a chosen order without wall-clock sleeps or real event queues.
final class DispatchQueue {
    static let main = DispatchQueue()
    var callbacks: [() -> Void] = []
    var deadlines: [FakeDeadline] = []

    func asyncAfter(deadline: FakeDeadline, execute work: @escaping () -> Void) {
        deadlines.append(deadline)
        callbacks.append(work)
    }

    func runNext() {
        precondition(!callbacks.isEmpty, "No pending callback to deliver")
        callbacks.removeFirst()()
    }

    func reset() {
        callbacks.removeAll()
        deadlines.removeAll()
    }
}

final class DonationReminderPanel {
    var presentations = 0
    var centers = 0
    var hides = 0
    var isVisible = false

    func makeKeyAndOrderFront(_ sender: Any?) {
        presentations += 1
        isVisible = true
    }

    func center() { centers += 1 }

    func orderOut(_ sender: Any?) {
        hides += 1
        isVisible = false
    }
}
