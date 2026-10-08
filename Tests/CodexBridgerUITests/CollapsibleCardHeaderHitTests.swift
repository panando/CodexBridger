import AppKit
import SwiftUI
import XCTest
@testable import CodexBridgerUI

/// Seam: the collapsing caption is the whole strip, not just the words.
///
/// Reported from the running app on 2026-10-08 (seventh review round): clicking the empty part of a
/// group header did nothing. The card's padding used to sit OUTSIDE the button, so the strip stopped
/// about 16pt short of each card edge and that margin was dead space. Reading the code cannot settle
/// whether a click lands, so these tests put the header in a real window and send a real click.
///
/// The geometry is measured rather than assumed: the window is taller than the strip, and the
/// strip's own height comes from the renderer.
@MainActor
final class CollapsibleCardHeaderHitTests: XCTestCase {

    private final class Recorder {
        var toggles = 0
    }

    private let width: CGFloat = 400
    private let height: CGFloat = 200

    func testTheStripIsAtLeastTheMinimumPointerTarget() {
        XCTAssertGreaterThanOrEqual(stripHeight, Metrics.minHitTarget)
    }

    /// Eight points inside the right edge, which is the dead margin that was reported.
    func testAClickInTheEmptyRightHandSideTogglesIt() throws {
        XCTAssertEqual(try clicks(x: width - 8, onOldLayout: false), 1,
                       "the blank part of the strip must toggle the group")
    }

    /// Five points inside the left edge, the strip's other dead end.
    func testAClickInTheLeftHandPaddingTogglesIt() throws {
        XCTAssertEqual(try clicks(x: 5, onOldLayout: false), 1,
                       "the padding at the left end of the strip is part of the target")
    }

    func testAClickOnTheCaptionTogglesIt() throws {
        XCTAssertEqual(try clicks(x: 60, onOldLayout: false), 1)
    }

    /// The target has a bottom edge: below the strip, still inside the card, is not the header.
    func testAClickBelowTheStripDoesNotToggleIt() throws {
        XCTAssertEqual(try clicks(x: width / 2, y: height - stripHeight - 10, onOldLayout: false), 0,
                       "the header's target must end where the strip ends")
    }

    // MARK: - The control

    /// The layout as it was before the fix, with the card's padding outside the button. The same
    /// click must do nothing there, which is what makes the tests above a measurement of the fix
    /// rather than a restatement of it.
    func testTheLayoutBeforeTheFixDidNotRespondAtThatPoint() throws {
        XCTAssertEqual(try clicks(x: width - 8, onOldLayout: true), 0,
                       "the pre-fix layout left a dead margin, so this is the change that fixed it")
        XCTAssertEqual(try clicks(x: width / 2, onOldLayout: true), 1,
                       "and it did respond in the middle, so the control is not vacuous")
    }

    // MARK: - Plumbing

    /// The strip's height, from the renderer: the click has to land inside it.
    private var stripHeight: CGFloat {
        let renderer = ImageRenderer(content: header(old: false, recorder: Recorder()).frame(width: width))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: nil, height: nil)
        return CGFloat(renderer.cgImage?.height ?? 0)
    }

    private func header(old: Bool, recorder: Recorder) -> AnyView {
        if old {
            // Exactly the shape this screen had before the fix, kept as the control.
            return AnyView(
                Button { recorder.toggles += 1 } label: {
                    SectionCaption("推理可见性") {
                        Image(systemName: "chevron.right").iconFont(.xs, weight: .semibold)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(Metrics.cardPadding)
            )
        }
        return AnyView(CollapsibleCardHeader(
            title: "推理可见性",
            isExpanded: false,
            accessibilityValue: "已折叠",
            onToggle: { recorder.toggles += 1 }
        ))
    }

    /// A press and a release into a real window, at the strip's own middle.
    private func clicks(x: CGFloat, y: CGFloat? = nil, onOldLayout old: Bool) throws -> Int {
        let recorder = Recorder()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Top-aligned, so the strip sits at the top and the rest of the window is below it.
        window.contentView = NSHostingView(
            rootView: header(old: old, recorder: recorder)
                .frame(width: width, height: height, alignment: .top)
        )
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        window.contentView?.layoutSubtreeIfNeeded()
        _ = NSApplication.shared
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        // AppKit window coordinates start at the bottom, so the strip's middle is that far up.
        let point = NSPoint(x: x, y: y ?? (height - stripHeight / 2))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ))
            window.sendEvent(event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return recorder.toggles
    }
}
