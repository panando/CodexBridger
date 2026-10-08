import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: the label column, which is the one thing that made the global settings screen
/// unreadable — every row showed `model_aut...` instead of a name.
final class GlobalSettingsLayoutTests: XCTestCase {

    /// The settings screen labels rows with config.toml key names, which are far longer than the
    /// prose labels the other screens use. If a longer key is ever added, this fails and forces
    /// the column to be reconsidered rather than silently truncating again.
    func testTheWideColumnFitsTheLongestKeyTheScreenShows() {
        // Derived from the catalog rather than hardcoded: the longest key changed when the page
        // was narrowed to two groups, and a hardcoded name would have needed a rewrite instead
        // of simply telling us the answer.
        let longest = try? XCTUnwrap(
            GlobalSettingsCatalog.settings.map(\.key).max(by: { $0.count < $1.count })
        )
        XCTAssertEqual(longest, "show_raw_agent_reasoning")
        // 7.0pt per character at Typography.label, measured from the rendered window (264pt
        // was still clipping this key by three characters), plus the info badge after it.
        let needed = CGFloat(longest!.count) * 7.0 + 24
        XCTAssertGreaterThanOrEqual(
            Metrics.settingsLabelWidth, needed,
            "the settings label column is narrower than the longest key it has to show"
        )
    }

    /// The prose-labelled screens were laid out against 100pt and must not move.
    func testTheOtherScreensKeepTheirNarrowColumn() {
        XCTAssertEqual(Metrics.labelColumnWidth, 100)
        XCTAssertGreaterThan(Metrics.settingsLabelWidth, Metrics.labelColumnWidth)
    }
}
