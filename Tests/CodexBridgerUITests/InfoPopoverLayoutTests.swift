import XCTest
import SwiftUI
@testable import CodexBridgerUI

/// Seam: the info popover hugs its text instead of occupying a fixed box.
///
/// Reported twice from the running app. First the box had a forced minimum width, so short
/// explanations sat in an oversized empty frame. Then, after that was "fixed", the Text was
/// constrained with `frame(width:)` — a *fixed* width — so every note became exactly 300pt wide
/// and the short ones looked worse than before. The comment claimed a short line still hugs its
/// text, which a fixed width can never do.
///
/// The earlier version of this file could only assert the cap, because `Snapshot` renders `Text`
/// as a solid black band and pixel extents say nothing about glyphs. These tests measure the
/// view's *intrinsic size* through `ImageRenderer` with an unconstrained proposal instead, which
/// is layout rather than pixels — so "short is narrower than long" is finally measurable.
@MainActor
final class InfoPopoverLayoutTests: XCTestCase {

    /// The size the view asks for when nothing constrains it, i.e. what the popover will be.
    private func intrinsicSize(of text: String) throws -> CGSize {
        let renderer = ImageRenderer(content: InfoPopoverContent(text: text))
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
        let long = try intrinsicSize(of:
            "会成为 config.toml 里的 [model_providers.<标识符>]，也要做文件名，所以不能有点号和空格")
        XCTAssertGreaterThanOrEqual(
            long.height, 24,
            "a long note must wrap onto more than one line"
        )
        XCTAssertLessThanOrEqual(
            long.width, InfoPopoverContent.maxWidth + 24,
            "a long note must not exceed the cap plus padding, got \(long.width)pt"
        )
    }

    /// The heart of it: width follows the text.
    func testWidthFollowsTheText() throws {
        let short = try intrinsicSize(of: "只影响名称")
        let long = try intrinsicSize(of:
            "会成为 config.toml 里的 [model_providers.<标识符>]，也要做文件名，所以不能有点号和空格")
        XCTAssertLessThan(
            short.width, long.width,
            "a shorter note must produce a narrower box: short=\(short.width) long=\(long.width)"
        )
    }
}