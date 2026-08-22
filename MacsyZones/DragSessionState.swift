//
// MacsyZones, macOS system utility for managing windows on your Mac.
//

import Foundation

/// Pure state used to make mouse/key event ordering deterministic.
/// AXUIElement and UI side effects deliberately stay outside this type so it can
/// be exercised by the lightweight tests in `tests/`.
struct DragSessionState: Equatable {
    enum Phase: Equatable {
        case idle
        case candidate(windowID: UInt32?)
        case dragging(windowID: UInt32)
    }

    private(set) var phase: Phase = .idle
    private(set) var isSnapKeyPressed = false

    var draggedWindowID: UInt32? {
        guard case let .dragging(windowID) = phase else { return nil }
        return windowID
    }

    var candidateWindowID: UInt32? {
        guard case let .candidate(windowID) = phase else { return nil }
        return windowID
    }

    var isDragging: Bool {
        draggedWindowID != nil
    }

    var wantsSnapOverlay: Bool {
        isDragging && isSnapKeyPressed
    }

    mutating func mouseDown(candidateWindowID: UInt32?) {
        phase = .candidate(windowID: candidateWindowID)
    }

    /// Starts a drag only when the moved window matches the mouse-down
    /// candidate. A nil candidate is allowed as an AX/focus fallback.
    @discardableResult
    mutating func confirmWindowMovement(windowID: UInt32) -> Bool {
        guard windowID != 0 else { return false }

        switch phase {
        case .idle:
            return false
        case let .candidate(candidateWindowID):
            guard candidateWindowID == nil || candidateWindowID == windowID else {
                return false
            }
            phase = .dragging(windowID: windowID)
            return true
        case let .dragging(activeWindowID):
            return activeWindowID == windowID
        }
    }

    mutating func snapKeyChanged(isPressed: Bool) {
        isSnapKeyPressed = isPressed
    }

    mutating func mouseUp() {
        phase = .idle
    }

    mutating func reset() {
        phase = .idle
        isSnapKeyPressed = false
    }
}
