import XCTest
@testable import CodexBridgerCore

/// Seam: the app shows its own icon, not a drawing of one.
///
/// The About pane was switched to the real application icon, but the welcome screen — the very
/// first thing a new user sees — kept a hand-drawn stand-in: a dark rounded square with a
/// `chevron.left.forwardslash.chevron.right` glyph on it. It looked intentional, which is what
/// made it easy to miss, and it advertised the wrong icon on the first screen.
final class ApplicationIconTests: XCTestCase {

    private static var uiDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexBridgerUI")
    }

    private func uiSources() throws -> [(name: String, text: String)] {
        var result: [(String, String)] = []
        let walker = FileManager.default.enumerator(
            at: Self.uiDirectory, includingPropertiesForKeys: nil
        )
        for case let url as URL in walker ?? FileManager.DirectoryEnumerator()
        where url.pathExtension == "swift" {
            result.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        XCTAssertFalse(result.isEmpty, "the interface sources must be found, not skipped")
        return result
    }

    /// The screen that introduces the app must show the app's real icon.
    func testTheWelcomeScreenUsesTheApplicationIcon() throws {
        let source = try XCTUnwrap(
            try uiSources().first { $0.name == "OnboardingView.swift" }?.text
        )
        XCTAssertTrue(source.contains("NSApplication.shared.applicationIconImage"),
                      "the welcome screen should show the bundle's icon")
    }

    /// The placeholder that used to stand in for it must not come back.
    func testNoScreenDrawsAPlaceholderForTheApplicationIcon() throws {
        for (name, text) in try uiSources() {
            // `app.dashed` is the deliberate fallback for when there is no running application
            // (a test rendering the view), so it is allowed.
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("///"), !trimmed.hasPrefix("//"), !trimmed.hasPrefix("*") else {
                    continue
                }
                XCTAssertFalse(
                    trimmed.contains("chevron.left.forwardslash.chevron.right"),
                    "\(name) draws a code glyph where the application icon belongs: \(trimmed)"
                )
            }
        }
    }

    /// Both places that present the app to the user agree on where the icon comes from.
    func testEveryPlaceThatShowsTheAppIconReadsItFromTheBundle() throws {
        let sources = try uiSources()
        let about = try XCTUnwrap(sources.first { $0.name == "SettingsView.swift" }?.text)
        XCTAssertTrue(about.contains("NSApplication.shared.applicationIconImage"))
        XCTAssertFalse(
            about.contains("chevron.left.forwardslash"),
            "the About pane should not carry a drawn stand-in either"
        )
    }
}