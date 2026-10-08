import XCTest
import SwiftUI
@testable import CodexBridgerUI

/// Seam: the info popover hugs its text and is tall enough for it.
///
/// Reported three times from the running app. First the box had a forced minimum width, so short
/// explanations sat in an oversized empty frame. Then, after that was "fixed", the Text was
/// constrained with `frame(width:)` — a *fixed* width — so every note became exactly 300pt wide
/// and the short ones looked worse than before. The third report (2026-10-08, eighth review) was
/// the clipping: `maxWidth` clamps the width the layout *reports* but proposes nothing to the
/// text, so the text was laid out unbroken and the box came back one line high, with the text
/// spilling over the rows above and below.
///
/// This file could not catch that, and its own guard was the reason: it asserted the wrapped
/// height was at least 24pt, which a single line already satisfies. Measuring the view against a
/// measured reference — same text, laid out at the box's own inner width — is what makes the
/// assertion mean "the text fits" instead of "the box has some height".
@MainActor
final class InfoPopoverLayoutTests: XCTestCase {

    /// The size the info popover asks for, i.e. what the running app's popover becomes.
    private func intrinsicSize(of text: String) throws -> CGSize {
        try intrinsicSize(of: InfoPopoverContent(text: text))
    }

    /// The size any view asks for when nothing constrains it.
    private func intrinsicSize<V: View>(of view: V) throws -> CGSize {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: nil, height: nil)
        let image = try XCTUnwrap(renderer.cgImage, "render failed")
        return CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
    }

    func testReadingWidthStaysComfortableButBounded() {
        XCTAssertLessThanOrEqual(
            InfoPopoverContent.maxWidth, 340,
            "the popover wraps instead of running the full width of the window"
        )
        XCTAssertGreaterThan(
            InfoPopoverContent.maxWidth, 200,
            "the popover stays wide enough to read comfortably"
        )
    }

    /// The reported defect: a short label rendered in a full-width box.
    func testAShortNoteDoesNotOccupyTheFullReadingWidth() throws {
        let short = try intrinsicSize(of: "只影响这个窗口里显示的名字")
        XCTAssertLessThan(
            short.width, InfoPopoverContent.maxWidth,
            "a short note must be narrower than the cap, got \(short.width)pt"
        )
    }

    /// A long note still wraps rather than running on forever.
    func testALongNoteWrapsAtTheReadingWidth() throws {
        let long = try intrinsicSize(of: Self.longNote)
        XCTAssertLessThanOrEqual(
            long.width, InfoPopoverContent.maxWidth + 24,
            "a long note must not exceed the cap plus padding, got \(long.width)pt"
        )
    }

    /// The reported clipping, measured. The box must be as tall as the text it holds, not one
    /// line tall with the rest spilling out.
    func testTheBoxIsTallEnoughForTheTextItHolds() throws {
        let box = try intrinsicSize(of: Self.longNote)
        // The same text, laid out at the width the box actually gives it. Independent of the
        // component: this is the height the text needs, measured separately.
        let innerWidth = InfoPopoverContent.naturalWidth(of: Self.longNote) > InfoPopoverContent.maxWidth
            ? InfoPopoverContent.maxWidth
            : InfoPopoverContent.naturalWidth(of: Self.longNote)
        let textHeight = try intrinsicSize(of:
            Text(Self.longNote)
                .font(Typography.help)
                .frame(width: innerWidth, alignment: .leading)
        )
        // The box is the text plus `Spacing.sm` of padding on each side.
        let expected = textHeight.height + Spacing.sm * 2
        XCTAssertEqual(
            box.height, expected, accuracy: 1,
            "the box must be as tall as its text: box=\(box.height) text=\(textHeight.height)"
        )
    }

    /// And it grows with the text, which is the half that was silently false before: both a one
    /// line note and a five line note reported the same height.
    func testTheBoxGrowsWithTheText() throws {
        let oneLine = try intrinsicSize(of: "一行很短")
        let manyLines = try intrinsicSize(of: Self.longNote)
        XCTAssertGreaterThan(
            manyLines.height, oneLine.height,
            "a longer note must produce a taller box: one=\(oneLine.height) many=\(manyLines.height)"
        )
    }

    /// Long enough to need several lines at the cap, and the kind of text the screen really has.
    static let longNote = "上一条拦下来的请示由谁审。user：你自己看（默认）；auto_review：自动审查，不打扰你。"

    /// The heart of it: width follows the text.
    func testWidthFollowsTheText() throws {
        let short = try intrinsicSize(of: "只影响名称")
        let long = try intrinsicSize(of: Self.longNote)
        XCTAssertLessThan(
            short.width, long.width,
            "a shorter note must produce a narrower box: short=\(short.width) long=\(long.width)"
        )
    }
}