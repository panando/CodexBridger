import AppKit
import SwiftUI
import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: EditableSelectField — the combo box used for the reviewer model.
///
/// The filtering rule is a pure static function, so it is asserted directly;
/// rendering covers the states the section can put it in.
@MainActor
final class EditableSelectFieldTests: XCTestCase {

    private let options = ["kimi-k2.7-code", "glm-5.2", "MiniMax-M3", "deepseek-v4-flash"]

    // MARK: Filtering

    func testEmptyQueryListsEveryOption() {
        XCTAssertEqual(
            EditableSelectField.filtered(options, by: ""),
            options
        )
        XCTAssertEqual(
            EditableSelectField.filtered(options, by: "   "),
            options
        )
    }

    func testQueryFiltersCaseInsensitivelyBySubstring() {
        XCTAssertEqual(EditableSelectField.filtered(options, by: "kimi"), ["kimi-k2.7-code"])
        XCTAssertEqual(EditableSelectField.filtered(options, by: "GLM"), ["glm-5.2"])
        XCTAssertEqual(EditableSelectField.filtered(options, by: "v4"), ["deepseek-v4-flash"])
    }

    /// A value no scan proved must still be typable: the field is not a picker,
    /// it is a text field with suggestions.
    func testUnknownValueIsKeptWhenFilteringIsNotUsed() {
        XCTAssertTrue(EditableSelectField.filtered(options, by: "my-own-slug").isEmpty)
    }

    // MARK: Rendering

    private func field(text: String, options: [String]) -> some View {
        EditableSelectField(
            options: options,
            text: .constant(text),
            accessibilityLabel: "自动审批模型"
        )
    }

    func testRendersWithCandidates() throws {
        let size = try XCTUnwrap(Snapshot.size(field(text: "", options: options), width: 520))
        XCTAssertGreaterThanOrEqual(size.width, 300)
    }

    func testRendersWithoutCandidates() throws {
        let size = try XCTUnwrap(Snapshot.size(field(text: "x", options: []), width: 520))
        XCTAssertGreaterThanOrEqual(size.width, 300)
    }

    func testRendersWithAManualValueOutsideTheList() throws {
        let size = try XCTUnwrap(
            Snapshot.size(field(text: "hand-typed-slug", options: options), width: 520)
        )
        XCTAssertGreaterThanOrEqual(size.width, 300)
    }
}
