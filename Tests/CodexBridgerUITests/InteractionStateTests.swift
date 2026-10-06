import XCTest
@testable import CodexBridgerUI

/// Seam: ControlInteractionState and SelectionCursor.
///
/// Components render from these states, so covering the transitions here covers the
/// hover/press/focus/disabled behaviour without needing to drive the UI.
final class InteractionStateTests: XCTestCase {

    func testStartsEnabledAndNeutral() {
        let state = ControlInteractionState()
        XCTAssertEqual(state.phase, .normal)
        XCTAssertTrue(state.isInteractive)
    }

    func testHoverProducesHoveredPhaseAndExitRestoresIt() {
        var state = ControlInteractionState()
        state.send(.hoverEnter)
        XCTAssertEqual(state.phase, .hovered)
        state.send(.hoverExit)
        XCTAssertEqual(state.phase, .normal)
    }

    func testPressWinsOverHoverAndFocus() {
        var state = ControlInteractionState()
        state.send(.hoverEnter)
        state.send(.focusGain)
        XCTAssertEqual(state.phase, .focusedHovered)
        state.send(.pressDown)
        XCTAssertEqual(state.phase, .pressed)
    }

    func testFocusAloneProducesFocusedPhase() {
        var state = ControlInteractionState()
        state.send(.focusGain)
        XCTAssertEqual(state.phase, .focused)
        state.send(.focusLoss)
        XCTAssertEqual(state.phase, .normal)
    }

    func testDisabledPhaseOverridesEverythingAndBlocksActivation() {
        var state = ControlInteractionState()
        state.send(.hoverEnter)
        state.send(.focusGain)
        state.send(.pressDown)
        state.send(.disable)
        XCTAssertEqual(state.phase, .disabled)
        XCTAssertFalse(state.isInteractive)
        XCTAssertFalse(state.send(.pressUp))
        XCTAssertEqual(state.activationCount, 0)
    }

    func testPressThatEndsInsideActivatesExactlyOnce() {
        var state = ControlInteractionState()
        state.send(.hoverEnter)
        state.send(.pressDown)
        XCTAssertTrue(state.send(.pressUp))
        XCTAssertEqual(state.activationCount, 1)
        // A stray second pressUp must not fire again.
        XCTAssertFalse(state.send(.pressUp))
        XCTAssertEqual(state.activationCount, 1)
    }

    func testDraggingOutCancelsThePress() {
        var state = ControlInteractionState()
        state.send(.hoverEnter)
        state.send(.pressDown)
        state.send(.hoverExit)
        XCTAssertEqual(state.phase, .normal)
        XCTAssertFalse(state.send(.pressUp), "drag-out must not activate")
        XCTAssertEqual(state.activationCount, 0)
    }

    func testReenablingClearsStaleHover() {
        var state = ControlInteractionState()
        state.send(.hoverEnter)
        state.send(.disable)
        state.send(.enable)
        XCTAssertEqual(state.phase, .normal, "a control must not come back pre-hovered")
    }

    func testEveryPhaseIsReachable() {
        var seen = Set<String>()
        var state = ControlInteractionState()
        seen.insert(String(describing: state.phase))
        state.send(.hoverEnter)
        seen.insert(String(describing: state.phase))
        state.send(.focusGain)
        seen.insert(String(describing: state.phase))
        state.send(.pressDown)
        seen.insert(String(describing: state.phase))
        state.send(.disable)
        seen.insert(String(describing: state.phase))
        XCTAssertEqual(seen.count, 5, "states covered: " + seen.sorted().joined(separator: ", "))
    }

    // MARK: - Keyboard cursor

    func testCursorStartsMovingFromNoSelection() {
        var cursor = SelectionCursor()
        cursor.move(by: 1, count: 4)
        XCTAssertEqual(cursor.index, 0)
        var backwards = SelectionCursor()
        backwards.move(by: -1, count: 4)
        XCTAssertEqual(backwards.index, 3)
    }

    func testCursorClampsAtBothEnds() {
        var cursor = SelectionCursor(index: 0)
        cursor.move(by: -1, count: 4)
        XCTAssertEqual(cursor.index, 0)
        cursor.move(by: 99, count: 4)
        XCTAssertEqual(cursor.index, 3)
    }

    func testCursorHandlesEmptyLists() {
        var cursor = SelectionCursor(index: 2)
        cursor.move(by: 1, count: 0)
        XCTAssertNil(cursor.index)
        var clamp = SelectionCursor(index: 5)
        clamp.clamp(count: 0)
        XCTAssertNil(clamp.index)
    }

    func testCursorClampsAfterTheOptionListShrinks() {
        var cursor = SelectionCursor(index: 4)
        cursor.clamp(count: 2)
        XCTAssertEqual(cursor.index, 1)
    }

    func testHomeAndEndKeys() {
        var cursor = SelectionCursor(index: 2)
        cursor.moveToStart()
        XCTAssertEqual(cursor.index, 0)
        cursor.moveToEnd(count: 5)
        XCTAssertEqual(cursor.index, 4)
    }

    func testHomeAndEndAreNoOpsWithoutAFocusedOption() {
        var cursor = SelectionCursor()
        cursor.moveToStart()
        XCTAssertNil(cursor.index)
        cursor.moveToEnd(count: 5)
        XCTAssertNil(cursor.index)
    }

    func testSelectingAnOutOfRangeOptionClamps() {
        var cursor = SelectionCursor()
        cursor.select(9, count: 3)
        XCTAssertEqual(cursor.index, 2)
        cursor.select(nil, count: 3)
        XCTAssertNil(cursor.index)
    }
}
