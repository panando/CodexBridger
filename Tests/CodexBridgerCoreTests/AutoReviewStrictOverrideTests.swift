import Foundation
import XCTest
@testable import CodexBridgerCore

/// Seam: the per-model strict override table read by auto-review probes.
///
/// The table exists because the harness sends strict=false for some models
/// (glm-5.3-flash observed) and the upstream rejects strict=true for them, so a
/// constant would call a working reviewer broken. Expected values come from the
/// reference probe's default table.
final class AutoReviewStrictOverrideTests: XCTestCase {

    func testDefaultTableDisablesStrictForTheObservedModel() {
        let table = AutoReviewStrictOverrides.default
        XCTAssertEqual(table.value(for: "glm-5.3-flash"), false)
    }

    func testUnknownModelsDefaultToStrict() {
        let table = AutoReviewStrictOverrides.default
        XCTAssertEqual(table.value(for: "kimi-k2.7-code"), true)
        XCTAssertEqual(table.value(for: "MiniMax-M3"), true)
    }

    func testLookupIsCaseSensitiveOnTheSlug() {
        let table = AutoReviewStrictOverrides.default
        // Slugs are case-sensitive on the wire; a different casing is a
        // different model and must not pick up the override.
        XCTAssertEqual(table.value(for: "GLM-5.3-FLASH"), true)
    }

    func testEntriesCanBeAddedAndRemoved() {
        var table = AutoReviewStrictOverrides.default
        table.set(false, for: "mimo-v2.6-flash")
        table.set(true, for: "glm-5.3-flash")
        XCTAssertEqual(table.value(for: "mimo-v2.6-flash"), false)
        XCTAssertEqual(table.value(for: "glm-5.3-flash"), true)
        table.remove("mimo-v2.6-flash")
        XCTAssertEqual(table.value(for: "mimo-v2.6-flash"), true)
    }

    func testParsesTheReferenceProbeEnvFormat() {
        let table = AutoReviewStrictOverrides(parsing: "glm-5.3-flash=false mimo-v2.6-flash=false")
        XCTAssertEqual(table.value(for: "glm-5.3-flash"), false)
        XCTAssertEqual(table.value(for: "mimo-v2.6-flash"), false)
        XCTAssertEqual(table.value(for: "kimi-k2.7-code"), true)
    }

    func testParsingIgnoresMalformedEntries() {
        let table = AutoReviewStrictOverrides(parsing: "glm-5.3-flash=false noise glm= kimi-k2.7-code=false")
        XCTAssertEqual(table.value(for: "glm-5.3-flash"), false)
        XCTAssertEqual(table.value(for: "kimi-k2.7-code"), false)
        XCTAssertEqual(table.value(for: "noise"), true)
        XCTAssertEqual(table.value(for: "glm"), true)
    }

    func testParsingTreatsOnlyFalseAsFalse() {
        let table = AutoReviewStrictOverrides(parsing: "a=false b=true c=0 d=1")
        XCTAssertEqual(table.value(for: "a"), false)
        XCTAssertEqual(table.value(for: "b"), true)
        XCTAssertEqual(table.value(for: "c"), true)
        XCTAssertEqual(table.value(for: "d"), true)
    }

    func testSurvivesJSONRoundTrip() throws {
        var table = AutoReviewStrictOverrides.default
        table.set(false, for: "deepseek-v4-pro")
        let data = try JSONEncoder().encode(table)
        let decoded = try JSONDecoder().decode(AutoReviewStrictOverrides.self, from: data)
        XCTAssertEqual(decoded.value(for: "glm-5.3-flash"), false)
        XCTAssertEqual(decoded.value(for: "deepseek-v4-pro"), false)
    }
}
