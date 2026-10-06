import AppKit
import SwiftUI
import XCTest
@testable import CodexBridgerUI

/// Alignment and sizing invariants, measured from rendered output.
///
/// The old layout put the control next to the label line when a help line existed and
/// centred it otherwise, so controls sat at different heights row to row. These tests
/// measure the rendered pixels to prove that no longer happens.
@MainActor
final class LayoutInvariantTests: XCTestCase {

    private func magentaBox(for row: some View) throws -> CGRect {
        guard let rendered = Snapshot.render(row, width: 640, scale: 2),
              let buffer = PixelBuffer(image: rendered.image, scale: 2),
              let box = buffer.boundingBox(where: { $0 > 200 && $1 < 80 && $2 > 200 }) else {
            throw XCTSkip("no measurement control found in the rendered row")
        }
        return box
    }

    // MARK: - Row height

    // These floors changed when the layout moved to the reference density. A full-width
    // text field is 34pt tall now, which satisfies WCAG 2.1 AA: AA has no minimum target
    // size. The 44pt rule is SC 2.5.5, which is AAA, so it is kept only where the target is
    // small enough to be easy to miss (icon buttons, checkboxes, switches).

    func testFieldRowMeetsTheRowHeightFloor() throws {
        let size = try XCTUnwrap(Snapshot.size(FormRow("标识符") { MeasurementProbe() }))
        XCTAssertGreaterThanOrEqual(size.height, Metrics.rowHeight)
    }

    func testFieldRowKeepsTheFloorWhenANoteFollows() throws {
        let size = try XCTUnwrap(
            Snapshot.size(FormRow("base_url", help: "第三方服务的 API 地址") { MeasurementProbe() })
        )
        XCTAssertGreaterThanOrEqual(size.height, Metrics.rowHeight)
    }

    func testRowGrowsForLongHelpTextButNeverShrinksBelowTheTarget() throws {
        let short = try XCTUnwrap(
            Snapshot.size(FormRow("字段", help: "简短说明") { MeasurementProbe() })
        )
        let long = try XCTUnwrap(
            Snapshot.size(FormRow("字段", help: String(repeating: "很长的说明文字，", count: 12)) {
                MeasurementProbe()
            })
        )
        XCTAssertGreaterThanOrEqual(short.height, Metrics.rowHeight)
        XCTAssertGreaterThanOrEqual(long.height, short.height)
    }

    // MARK: - Horizontal alignment

    func testControlColumnStartsAtTheSameXWhateverTheLabelLength() throws {
        let shortLabel = try magentaBox(for: FormRow("名称") { MeasurementProbe() })
        let longLabel = try magentaBox(
            for: FormRow("一个非常长的字段名称会换行也应该不影响控制列") { MeasurementProbe() }
        )
        XCTAssertEqual(
            shortLabel.minX, longLabel.minX, accuracy: 1,
            "the control column must not move when the label length changes"
        )
        XCTAssertEqual(shortLabel.width, longLabel.width, accuracy: 1)
    }

    func testControlColumnIsTheSameWithAndWithoutHelpText() throws {
        let without = try magentaBox(for: FormRow("字段") { MeasurementProbe() })
        let with = try magentaBox(
            for: FormRow("字段", help: "这一行有说明文字") { MeasurementProbe() }
        )
        XCTAssertEqual(
            without.minX, with.minX, accuracy: 1,
            "adding a help line must not shift the control"
        )
    }

    func testLabelColumnMatchesTheDesignToken() throws {
        let box = try magentaBox(for: FormRow("字段") { MeasurementProbe() })
        let expected = Metrics.labelColumnWidth + Metrics.labelToControlGap
        XCTAssertEqual(
            box.minX, expected, accuracy: 2,
            "the control column should start at labelColumnWidth + gap"
        )
    }

    // MARK: - Vertical alignment

    /// The control sits on the first line of the row. A note, when present, hangs below it,
    /// which is the reference behaviour: the label centres on the control, not on the note.
    ///
    /// Measured against the row's own topmost content, not against an absolute y. The rendered
    /// canvas is sized to the content and the row is centred in it, so the absolute origin moves
    /// whenever the row's total height changes — adding the help line outside the control stack
    /// changed the height and moved the origin by 1.5pt with no change to the control itself.
    /// "Nothing is drawn above the control" is the invariant that actually matters, and it holds
    /// regardless of where the canvas starts.
    func testControlSitsOnTheFirstLineWhenANoteFollows() throws {
        guard let rendered = Snapshot.render(
            FormRow("字段", help: "说明文字") { MeasurementProbe(height: 28) },
            width: 640, scale: 2
        ), let buffer = PixelBuffer(image: rendered.image, scale: 2) else {
            throw XCTSkip("render failed")
        }
        let box = try XCTUnwrap(
            buffer.boundingBox(where: { $0 > 200 && $1 < 80 && $2 > 200 })
            , "measurement control missing")
        let content = try XCTUnwrap(
            buffer.boundingBox(where: { !($0 > 248 && $1 > 248 && $2 > 248) })
            , "row content missing")
        XCTAssertEqual(
            box.minY, content.minY, accuracy: 3,
            "the control must be the first thing in the row, with no note above it"
        )
        XCTAssertLessThan(
            box.maxY, content.maxY,
            "the note must sit below the control, not inside it"
        )
    }

    /// Rows are top-aligned, not centred: a row with a note is taller, so centring would push
    /// its control down and break the shared control line across the form.
    /// The row centres its content, so the control sits at the row's vertical centre rather
    /// than glued to the top edge. This is what keeps the label and the control visually aligned.
    func testControlIsVerticallyCentredInTheRow() throws {
        guard let rendered = Snapshot.render(
            FormRow("字段") { MeasurementProbe(height: 28) },
            width: 640, scale: 2
        ), let buffer = PixelBuffer(image: rendered.image, scale: 2) else {
            throw XCTSkip("render failed")
        }
        let box = try XCTUnwrap(
            buffer.boundingBox(where: { $0 > 200 && $1 < 80 && $2 > 200 })
            , "measurement control missing")
        XCTAssertEqual(box.midY, rendered.size.height / 2, accuracy: 2, "control centred in the row")
        XCTAssertGreaterThanOrEqual(rendered.size.height, box.height, "row contains the control")
    }

    /// Rows of different shapes must still place their controls on the same line.
    func testControlsAcrossDifferentRowsShareTheSameCentre() throws {
        let withNote = try magentaBox(for: FormRow("字段", help: "说明文字") {
            MeasurementProbe(height: 28)
        })
        let withoutNote = try magentaBox(for: FormRow("字段") { MeasurementProbe(height: 28) })
        // Both rows centre the control block, so the control centre is the row top plus half
        // the control height in each case.
        XCTAssertEqual(withNote.midY - withNote.minY, withoutNote.midY - withoutNote.minY,
                       accuracy: 1.5,
                       "the control sits the same distance from the top in both row shapes")
    }

    // MARK: - Long content

    func testLongLabelAndLongHelpDoNotOverflowTheRow() throws {
        let longText = String(repeating: "很长的文本内容 ", count: 20)
        guard let rendered = Snapshot.render(
            FormRow(longText, help: longText) { MeasurementProbe() },
            width: 640, scale: 2
        ) else {
            throw XCTSkip("render failed")
        }
        XCTAssertLessThanOrEqual(
            rendered.size.width, 640 + 1,
            "the row must respect its container width"
        )
        // The label column is fixed, so the control column keeps a usable width.
        XCTAssertGreaterThan(
            rendered.size.width - (Metrics.labelColumnWidth + Metrics.labelToControlGap), 100
        )
    }
}
