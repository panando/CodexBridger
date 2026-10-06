import XCTest
@testable import CodexBridgerCore

/// Seam: TOMLDocument public API.
///
/// The riskiest thing CodexBridger does is edit a config.toml it does not own.
/// These tests pin down that unrelated content survives untouched.
final class TOMLDocumentTests: XCTestCase {

    func testSetsTopLevelKeyBeforeFirstTable() {
        let original = [
            "model = \"old\"",
            "personality = 'pragmatic'",
            "",
            "[features]",
            "goals = true"
        ].joined(separator: TOMLDocument.newline)
        var document = TOMLDocument(text: original)
        document.setTopLevel(key: "model", rawValue: "\"new\"")
        XCTAssertEqual(document.topLevelString("model"), "new")
        XCTAssertTrue(document.text.contains("personality = 'pragmatic'"))
        XCTAssertTrue(document.text.contains("[features]"))
        XCTAssertTrue(document.text.hasSuffix("goals = true"))
    }

    func testInsertsMissingTopLevelKeyIntoTopLevelRegion() {
        var document = TOMLDocument(text: "sandbox_mode = 'workspace-write'\n\n[features]\ngoals = true\n")
        document.setTopLevel(key: "model_provider", rawValue: "\"demo\"")
        let lines = document.text.components(separatedBy: TOMLDocument.newline)
        let providerIndex = lines.firstIndex { $0.hasPrefix("model_provider =") }
        let featuresIndex = lines.firstIndex { $0 == "[features]" }
        XCTAssertNotNil(providerIndex)
        XCTAssertNotNil(featuresIndex)
        XCTAssertLessThan(providerIndex ?? 999, featuresIndex ?? 0,
                          "top-level keys must stay above the first table header")
    }

    func testReplacesMultilineArrayValueWithoutLeavingOrphans() {
        let original = [
            "notify = [",
            "    \"/usr/local/bin/one\",",
            "    'turn-ended'",
            "]",
            "model = \"a\"",
            "",
            "[features]",
            "goals = true"
        ].joined(separator: TOMLDocument.newline)
        var document = TOMLDocument(text: original)
        document.setTopLevel(key: "notify", rawValue: "[\"/bin/other\"]")
        XCTAssertFalse(document.text.contains("/usr/local/bin/one"))
        XCTAssertFalse(document.text.contains("turn-ended"))
        XCTAssertTrue(document.text.contains("model = \"a\""))
        XCTAssertEqual(document.topLevelString("notify"), "[\"/bin/other\"]")
    }

    func testRemoveTopLevelKeyLeavesRestIntact() {
        var document = TOMLDocument(text: "a = 1\nb = 2\nc = 3\n\n[t]\nx = 1\n")
        document.removeTopLevel(key: "b")
        XCTAssertNil(document.topLevelRawValue(for: "b"))
        XCTAssertEqual(document.topLevelString("a"), "1")
        XCTAssertEqual(document.topLevelString("c"), "3")
        XCTAssertTrue(document.text.contains("[t]"))
    }

    func testTablePathsReadsQuotedAndNestedHeaders() {
        let text = [
            "model = \"m\"",
            "",
            "[model_providers.cpa]",
            "name = \"CPA\"",
            "",
            "[model_providers.cpa.auth]",
            "command = \"/bin/token\"",
            "",
            "[hooks.state.'/Users/me/x/hooks.json:pre_tool_use:0:0']",
            "trusted_hash = 'sha256:abc'",
            "",
            "[[skills.config]]",
            "enabled = false"
        ].joined(separator: TOMLDocument.newline)
        let document = TOMLDocument(text: text)
        let paths = document.tablePaths()
        XCTAssertEqual(paths[0], ["model_providers", "cpa"])
        XCTAssertEqual(paths[1], ["model_providers", "cpa", "auth"])
        XCTAssertEqual(paths[2], ["hooks", "state", "/Users/me/x/hooks.json:pre_tool_use:0:0"])
        XCTAssertEqual(paths[3], ["skills", "config"])
    }

    func testReplaceTableRegionSwallowsSubTables() {
        let text = [
            "model = \"m\"",
            "",
            "[model_providers.demo]",
            "name = \"old\"",
            "",
            "[model_providers.demo.auth]",
            "command = \"/bin/old\"",
            "",
            "[model_providers.other]",
            "name = \"other\"",
            "",
            "[features]",
            "goals = true"
        ].joined(separator: TOMLDocument.newline)
        var document = TOMLDocument(text: text)
        document.replaceTableRegion(rootPath: ["model_providers", "demo"], rendered: [
            "[model_providers.demo]",
            "name = \"new\""
        ])
        XCTAssertTrue(document.text.contains("name = \"new\""))
        XCTAssertFalse(document.text.contains("/bin/old"), "stale sub-table must be replaced")
        XCTAssertTrue(document.text.contains("[model_providers.other]"))
        XCTAssertTrue(document.text.contains("[features]"))
        XCTAssertTrue(document.text.contains("goals = true"))
    }

    func testReplaceMissingTableAppendsOnce() {
        var document = TOMLDocument(text: "model = \"m\"\n\n[features]\ngoals = true\n")
        document.replaceTableRegion(rootPath: ["model_providers", "new"], rendered: [
            "[model_providers.new]",
            "name = \"N\""
        ])
        let count = document.text.components(separatedBy: "[model_providers.new]").count - 1
        XCTAssertEqual(count, 1)
    }

    func testRemoveTableRegionCollapsesBlankLine() {
        let text = "model = \"m\"\n\n[model_providers.demo]\nname = \"d\"\n\n[features]\ngoals = true\n"
        var document = TOMLDocument(text: text)
        document.removeTableRegion(rootPath: ["model_providers", "demo"])
        XCTAssertFalse(document.text.contains("model_providers.demo"))
        XCTAssertTrue(document.text.contains("[features]"))
        XCTAssertFalse(document.text.contains("\n\n\n"), "no triple newline left behind")
    }

    func testRoundTripsTextExactly() {
        let text = "a = 1\n\n[b]\nc = 'd'\n"
        XCTAssertEqual(TOMLDocument(text: text).text, text)
    }

    func testValueWriterQuotesKeysAndEscapesStrings() {
        XCTAssertEqual(TOMLValueWriter.keyString("X-Example-Header"), "X-Example-Header")
        XCTAssertEqual(TOMLValueWriter.keyString("has space"), "\"has space\"")
        XCTAssertEqual(TOMLValueWriter.bool(true), "true")
        XCTAssertEqual(TOMLValueWriter.stringArray(["a", "b"]), "[\"a\", \"b\"]")
        XCTAssertEqual(
            TOMLValueWriter.inlineTable([("z", "1"), ("a", "2")]),
            "{ a = \"2\", z = \"1\" }"
            , "inline tables are emitted in a stable sorted order")
        XCTAssertEqual(TOMLValueWriter.string("say \"hi\""), "\"say \\\"hi\\\"\"")
    }
}
