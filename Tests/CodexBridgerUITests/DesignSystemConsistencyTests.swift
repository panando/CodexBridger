import XCTest
import AppKit
@testable import CodexBridgerUI

/// Architectural guard: the design tokens are the only source of type, colour and stroke sizes.
///
/// Tokens only help if nothing bypasses them. Before this test the UI carried 23 hardcoded font
/// sizes (8 of them values with no token at all), 6 raw Color.white uses sitting next to an
/// unused textOnAccent token, and 5 hardcoded border widths. Nothing stopped that from growing.
/// This fails the moment one comes back.
final class DesignSystemConsistencyTests: XCTestCase {

    /// Sources/CodexBridgerUI, reached from this file without a build-time path setting.
    private var uiRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CodexBridgerUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/CodexBridgerUI")
    }

    /// Every UI source except the token file itself, which is where raw values are allowed.
    private func sources() throws -> [(name: String, text: String)] {
        let enumerator = FileManager.default.enumerator(
            at: uiRoot, includingPropertiesForKeys: nil
        )
        var found: [(String, String)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard url.lastPathComponent != "DesignTokens.swift" else { continue }
            found.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        XCTAssertFalse(found.isEmpty, "the UI sources should be found at \(uiRoot.path)")
        return found
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return (regex?.matches(in: text, range: range) ?? []).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    /// The sidebar footer and the editor action bar sit side by side. Their top rules only line
    /// up if both use the same height, which is exactly what they used to get wrong: one took
    /// 8pt of vertical padding and the other 12pt, so the two dividers were visibly offset.
    func testBothBottomBarsShareOneHeight() throws {
        let sidebar = try XCTUnwrap(try sources().first { $0.name == "ContentView.swift" })
        let editor = try XCTUnwrap(try sources().first { $0.name == "ProviderConfigView.swift" })

        for (name, source) in [("ContentView", sidebar), ("ProviderConfigView", editor)] {
            XCTAssertTrue(
                source.text.contains(".frame(height: Metrics.actionBarHeight)"),
                name + " must size its bottom bar with the shared token"
            )
            XCTAssertTrue(
                source.text.contains(".padding(.vertical, Metrics.actionBarVerticalPadding)"),
                name + " must pad its bottom bar with the shared token"
            )
        }
    }

    func testNoLiteralFontSizes() throws {
        var offenders: [String] = []
        for source in try sources() {
            for hit in matches(#"\.font\(\.system\(size: [0-9]"#, in: source.text) {
                offenders.append(source.name + ": " + hit)
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "font sizes must come from Typography or IconSize: " + offenders.joined(separator: ", ")
        )
    }

    func testNoRawSystemColors() throws {
        let names = "white|black|gray|grey|blue|red|green|orange|yellow|purple|pink|brown|cyan|magenta"
        var offenders: [String] = []
        for source in try sources() {
            for hit in matches("Color\\.(" + names + ")\\b", in: source.text) {
                offenders.append(source.name + ": " + hit)
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "colours must come from Palette: " + offenders.joined(separator: ", ")
        )
    }

    func testNoLiteralStrokeOrRadius() throws {
        var offenders: [String] = []
        for source in try sources() {
            offenders += matches(#"lineWidth: [0-9]"#, in: source.text).map { source.name + ": " + $0 }
            offenders += matches(#"cornerRadius: [0-9]"#, in: source.text).map { source.name + ": " + $0 }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "strokes and radii must come from Radius/Metrics: " + offenders.joined(separator: ", ")
        )
    }

    func testNoHandRolledLabelColumnSpacer() throws {
        var offenders: [String] = []
        // The one legitimate use is inside LabelColumnSpacer own definition; the guard is
        // about call sites, so that single definition is exempted before scanning.
        let definition = #"public struct LabelColumnSpacer: View \{[\s\S]*?\n\}"#
        for source in try sources() {
            var text = source.text
            if source.name == "FormRow.swift",
               let range = text.range(of: definition, options: .regularExpression) {
                text = text.replacingCharacters(in: range, with: "")
            }
            for hit in matches(#"Color\.clear\.frame\(width: Metrics\.labelColumnWidth"#, in: text) {
                offenders.append(source.name + ": " + hit)
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "use LabelColumnSpacer: " + offenders.joined(separator: ", ")
        )
    }

    func testTheIconScaleHasNoDuplicateSizes() {
        let sizes: [CGFloat] = [
            IconSize.xs.rawValue, IconSize.s.rawValue, IconSize.m.rawValue,
            IconSize.l.rawValue, IconSize.glyph.rawValue, IconSize.hero.rawValue
        ]
        XCTAssertEqual(Set(sizes).count, sizes.count, "each icon step is a distinct size")
        XCTAssertEqual(sizes, sizes.sorted(), "the scale is ordered")
    }

    func testTheTypeScaleHasNoDuplicateValuesForDifferentNames() {
        // label/control/caption used to be separate names for the same value, which made the
        // scale look larger than it was. They are aliases now, so this documents the real set.
        XCTAssertEqual(Typography.label, Typography.body)
        XCTAssertEqual(Typography.control, Typography.body)
        XCTAssertEqual(Typography.caption, Typography.help)
        XCTAssertNotEqual(Typography.body, Typography.help)
    }

    /// A View whose body returns its own type recurses forever and blows the stack.
    ///
    /// This shipped once: a token-migration pass rewrote the body of a spacer component so that
    /// it rendered itself, which made the whole app crash on launch with SIGSEGV and crashed
    /// every render test. The crash surfaces far away from the cause (deep in SwiftUI metadata),
    /// so it is checked mechanically instead of by review.
    func testNoViewBodyRendersItself() throws {
        var offenders: [String] = []
        let pattern = try NSRegularExpression(
            pattern: #"(?:struct|enum)\s+(\w+)\s*:\s*View\b[^{]*\bvar\s+body\s*:\s*some\s+View\s*\{\s*\n\s*\1\s*\("#,
            options: [.dotMatchesLineSeparators]
        )
        for source in try sources() {
            let range = NSRange(source.text.startIndex..., in: source.text)
            for match in pattern.matches(in: source.text, range: range) {
                if let nameRange = Range(match.range(at: 1), in: source.text) {
                    offenders.append(source.name + ": " + String(source.text[nameRange]))
                }
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "a View body must not render its own type: " + offenders.joined(separator: ", ")
        )
    }
}
