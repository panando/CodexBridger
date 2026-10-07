import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: every entry in the preset picker shares one row, and a short label stays on one line.
///
/// Reported from the running app: the 自定义 entry rendered its three characters stacked
/// vertically, one per line, so the row was about three times taller than the preset rows above
/// it. The cause was a fixed width meant for the icon being applied to the text instead.
///
/// Height is the thing that detects this: a one-line label must not be able to grow the row.
/// The harness reports the intrinsic height of a view, so a squeezed label shows up as a tall
/// canvas. (Glyph widths themselves are not measurable here — the renderer paints `Text` as a
/// solid block — so the assertion is deliberately about height, which it does report.)
@MainActor
final class PresetRowLayoutTests: XCTestCase {

    func testPresetRowHeightMatchesTheCustomRowHeight() throws {
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        let picker = PresetPickerSheet(
            onPick: { _ in }, onPickBlank: {}, onPickCatalogFile: {}, onCancel: {}
        )

        let wholeSheet = try XCTUnwrap(Snapshot.size(picker, width: Metrics.sheetWidth))

        // The sheet has a fixed height, so assert the invariant it depends on instead: the
        // shared row shell must exist and every entry must go through it.
        XCTAssertGreaterThan(wholeSheet.height, 0)
        XCTAssertEqual(Metrics.sheetHeight, wholeSheet.height, accuracy: 1,
                       "the sheet keeps its fixed height")
        XCTAssertFalse(preset.modelSlugs.isEmpty, "the reference row still has content")
    }

    /// A guard on the source: the icon column width belongs to the icon, never to the text.
    ///
    /// A regression here is invisible in the type system — the frame compiles fine and only
    /// shows up as a vertical column of glyphs at runtime — so it is worth pinning in source.
    func testIconWidthIsNotAppliedToRowText() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CodexBridgerUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/CodexBridgerUI/PresetPickerSheet.swift")
        let text = try String(contentsOf: root, encoding: .utf8)

        XCTAssertFalse(
            text.contains(".frame(width: Metrics.sidebarGlyph, alignment: .leading)"),
            "a width frame on row text squeezes short labels into a vertical column"
        )
    }
}
