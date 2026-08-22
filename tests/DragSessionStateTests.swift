import Foundation

@main
struct DragSessionStateTests {
    static func main() {
        testSnapKeyThenDragMatchesDragThenSnapKey()
        testWrongWindowCannotHijackCandidate()
        testWrongWindowCannotHijackActiveDrag()
        testMouseUpPreservesPhysicalKeyState()
        testResetClearsEverything()
        print("DragSessionStateTests: PASS")
    }

    private static func testSnapKeyThenDragMatchesDragThenSnapKey() {
        var keyFirst = DragSessionState()
        keyFirst.snapKeyChanged(isPressed: true)
        keyFirst.mouseDown(candidateWindowID: 42)
        precondition(keyFirst.confirmWindowMovement(windowID: 42))

        var dragFirst = DragSessionState()
        dragFirst.mouseDown(candidateWindowID: 42)
        precondition(dragFirst.confirmWindowMovement(windowID: 42))
        dragFirst.snapKeyChanged(isPressed: true)

        precondition(keyFirst == dragFirst)
        precondition(keyFirst.wantsSnapOverlay)
    }

    private static func testWrongWindowCannotHijackCandidate() {
        var state = DragSessionState()
        state.mouseDown(candidateWindowID: 42)

        precondition(!state.confirmWindowMovement(windowID: 99))
        precondition(!state.isDragging)
        precondition(state.confirmWindowMovement(windowID: 42))
        precondition(state.draggedWindowID == 42)
    }

    private static func testWrongWindowCannotHijackActiveDrag() {
        var state = DragSessionState()
        state.mouseDown(candidateWindowID: 42)
        precondition(state.confirmWindowMovement(windowID: 42))

        precondition(state.confirmWindowMovement(windowID: 42))
        precondition(!state.confirmWindowMovement(windowID: 99))
        precondition(state.draggedWindowID == 42)
    }

    private static func testMouseUpPreservesPhysicalKeyState() {
        var state = DragSessionState()
        state.snapKeyChanged(isPressed: true)
        state.mouseDown(candidateWindowID: 42)
        precondition(state.confirmWindowMovement(windowID: 42))
        state.mouseUp()

        precondition(!state.isDragging)
        precondition(state.isSnapKeyPressed)
        precondition(!state.wantsSnapOverlay)
    }

    private static func testResetClearsEverything() {
        var state = DragSessionState()
        state.snapKeyChanged(isPressed: true)
        state.mouseDown(candidateWindowID: 42)
        precondition(state.confirmWindowMovement(windowID: 42))
        state.reset()

        precondition(state == DragSessionState())
    }
}
