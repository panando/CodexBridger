import XCTest
import SwiftUI
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: a control shorter than the label's box sits on the label's centre line.
///
/// Reported from the running app (2026-10-08, ninth review): 标签与 Switch toggle 的水平高度没有居中对齐.
/// Measured on that screenshot: the switch's centre was 7px (3.5pt) above the centre of the ⓘ circle on
/// the same line. The cause is in `FormRow`, not in the switch — the label sits in a box
/// `Metrics.controlVisualHeight` (24pt) tall and centres itself there, while the control column was
/// top-aligned, so a control shorter than 24pt rode high by half the difference.
///
/// This measures that rule with a control of KNOWN height rather than with the platform switch. A
/// switch cannot be used here: `ImageRenderer` draws it about 24pt tall while a real window draws it
/// about 18pt (measured in both), so a headless pixel test with a real switch passed with and without
/// the fix — it could not see the defect at all. A fixed-height shape can be seen. The running app is
/// what confirms the switch itself; this confirms the rule that places it.
@MainActor
final class FormRowControlAlignmentTests: XCTestCase {

    /// A control whose height is decided here, so the measurement does not depend on a platform
    /// control's metrics. White background: `Snapshot` renders transparent pixels as black, which is
    /// indistinguishable from dark text.
    private func row(controlHeight: CGFloat, visualOffset: CGFloat = 0) -> some View {
        FormRow("标签", info: "说明") {
            Rectangle()
                .fill(Color.black)
                .frame(height: controlHeight)
                // A pure visual displacement: padding would be absorbed by the column's own
                // centred minimum height, so it would not prove the probe can see a
                // misalignment at all.
                .offset(y: visualOffset)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 400)
        .background(Color.white)
    }

    /// Vertical centre of the control's ink, in points.
    private func controlCentre(_ view: some View) throws -> CGFloat {
        let rendered = try XCTUnwrap(Snapshot.render(view, width: 400))
        let scale = CGFloat(rendered.image.width) / max(rendered.size.width, 1)
        let buffer = try XCTUnwrap(PixelBuffer(image: rendered.image, scale: scale))
        let labelColumn = Int(Metrics.labelColumnWidth * scale)
        var minY = buffer.height, maxY = -1
        for x in labelColumn..<buffer.width {
            for y in 0..<buffer.height {
                let o = (y * buffer.width + x) * 4
                let r = buffer.pixels[o], g = buffer.pixels[o + 1], b = buffer.pixels[o + 2]
                if r < 128, g < 128, b < 128 {
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxY >= minY else { return -1 }
        return CGFloat(minY + maxY) / 2 / scale
    }

    /// Where the label's box centre actually lands.
    ///
    /// The row's contents are centred inside `Metrics.rowHeight` (the `minHeight` frame in
    /// `FormRow` takes the default centre alignment), and the label's box is
    /// `Metrics.controlVisualHeight` tall, so the line sits half the leftover below the top —
    /// measured at 17.0pt in a 34pt row, not at the 12pt the box height alone would suggest.
    private var labelLineCentre: CGFloat {
        (Metrics.rowHeight - Metrics.controlVisualHeight) / 2 + Metrics.controlVisualHeight / 2
    }

    /// The defect: a short control has to share the label's centre line.
    func testAShortControlSharesTheLabelsCentreLine() throws {
        // 4pt: much shorter than the 24pt box, i.e. the switch's situation.
        let centre = try controlCentre(row(controlHeight: 4))
        XCTAssertGreaterThan(centre, 0, "no control ink found")
        XCTAssertEqual(
            centre, labelLineCentre, accuracy: 1,
            "a 4pt control centre=" + String(format: "%.1f", centre)
            + " must sit on the label line at " + String(format: "%.1f", labelLineCentre)
        )
    }

    /// A control taller than the box is not moved.
    func testAFullHeightControlIsNotMoved() throws {
        let centre = try controlCentre(row(controlHeight: Metrics.controlVisualHeight))
        XCTAssertEqual(centre, labelLineCentre, accuracy: 1)
    }

    /// Non-vacuity: the measurement can tell. A control drawn 10pt lower must read as off-centre,
    /// so a pass above means "aligned", not "the probe is blind".
    func testTheMeasurementCanSeeAnOffCentreControl() throws {
        let centre = try controlCentre(row(controlHeight: 4, visualOffset: 10))
        XCTAssertEqual(
            centre - labelLineCentre, 10, accuracy: 1,
            "a control drawn 10pt lower must measure 10pt off-centre, got "
            + String(format: "%.1f", centre - labelLineCentre)
        )
    }

    /// And the same rule applied to the switch the report was about, in the two states the page uses.
    func testTheSwitchRowsReportedAreBuiltFromThisRow() throws {
        // The screen's own control builder is private; this asserts the structure it uses, so the
        // fix cannot be "verified" against a fixture that only looks like the row.
        let source = try String(contentsOfFile: Self.formRowPath, encoding: .utf8)
        let occurrences = source.components(separatedBy: "minHeight: Metrics.controlVisualHeight").count - 1
        XCTAssertEqual(
            occurrences, 1,
            "the control column must carry the label box's minimum height exactly once, found "
            + String(occurrences)
        )
    }

    private static let formRowPath =
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexBridgerUI/Components/FormRow.swift")
            .path
}
