import XCTest
@testable import CodexBridgerCore

/// Seam: the interface language and its lookup table.
final class LocalizationTests: XCTestCase {

    func testChineseIsTheDefaultSource() {
        XCTAssertEqual(Localization.text("保存", language: .chinese), "保存")
    }

    func testEnglishIsLookedUpByTheChineseSource() {
        XCTAssertEqual(Localization.text("保存", language: .english), "Save")
        XCTAssertEqual(Localization.text("模型提供商", language: .english), "Providers")
    }

    func testAutoReviewStringsAreTranslated() {
        XCTAssertEqual(Localization.text("自动审批模型", language: .english), "Auto-review model")
        XCTAssertEqual(Localization.text("一键检测", language: .english), "Run check")
        XCTAssertEqual(
            Localization.text("先在「模型配置」里添加模型，检测才有对象", language: .english),
            "Add a model under Model configuration first"
        )
    }

    /// Partial coverage must degrade to readable Chinese, never to a bare key.
    func testAnUntranslatedStringFallsBackToItsSource() {
        let source = "这一句还没有翻译"
        XCTAssertEqual(Localization.text(source, language: .english), source,
                       "an unknown string must come back unchanged, not empty")
    }

    func testSystemResolvesFromThePreferredLanguages() {
        XCTAssertEqual(Localization.resolved(.system, preferred: ["zh-Hans-CN", "en-US"]), .chinese)
        XCTAssertEqual(Localization.resolved(.system, preferred: ["en-US", "zh-Hans"]), .english)
        XCTAssertEqual(Localization.resolved(.system, preferred: ["fr-FR"]), .chinese,
                       "an unrelated system language falls back to the source language")
    }

    func testAnExplicitChoiceIsNotOverriddenByTheSystem() {
        XCTAssertEqual(Localization.resolved(.english, preferred: ["zh-Hans"]), .english)
        XCTAssertEqual(Localization.resolved(.chinese, preferred: ["en-US"]), .chinese)
    }

    // MARK: - Generated warnings

    /// The guard builds its warnings around a host or a URL, so they cannot live in the table.
    func testALoopbackWarningIsRebuiltInEnglish() {
        let message = "base_url 指向本机（127.0.0.1），只有本地服务运行时 Codex 才能用。"
        let english = Localization.warning(message, language: .english)
        XCTAssertTrue(english.contains("127.0.0.1"), "the host must survive translation")
        XCTAssertFalse(english.contains("指向本机"), "the Chinese must be gone")
    }

    func testAnInvalidAddressWarningKeepsTheAddress() {
        let english = Localization.warning(
            "base_url 不是一个合法的网址：ht!tp://x", language: .english
        )
        XCTAssertTrue(english.contains("ht!tp://x"), "the offending value must survive")
    }

    func testAMissingAddressWarningIsTranslated() {
        let english = Localization.warning(
            "没有填写 base_url，写进配置之前请先补上。", language: .english
        )
        XCTAssertFalse(english.contains("没有填写"))
    }

    /// Chinese keeps the message exactly as generated.
    func testChineseWarningsAreUntouched() {
        let message = "base_url 指向本机（127.0.0.1），只有本地服务运行时 Codex 才能用。"
        XCTAssertEqual(Localization.warning(message, language: .chinese), message)
        XCTAssertEqual(Localization.warning(message, language: .system), message,
                       "an unset system language resolves from the preferred list")
    }

    /// An unrecognised message must pass through rather than vanish.
    func testAnUnknownWarningIsPassedThrough() {
        let message = "这条提示还没有对应的英文"
        XCTAssertEqual(Localization.warning(message, language: .english), message)
    }

    /// A duplicate key in the table is a runtime crash, not a compile error.
    ///
    /// `Dictionary` literal initialisation traps on a repeated key, so a copy-paste slip in the
    /// table takes the whole process down the first time that table is built. Checking the source
    /// turns that into a test failure instead of a crash in front of the user.
    func testTheTableHasNoDuplicateKeys() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/CodexBridgerCore/Localization.swift"),
            encoding: .utf8
        )
        let body = try XCTUnwrap(source.components(separatedBy: "english: [String: String]").last)
        var keys: [String] = []
        for line in body.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\"") else { continue }
            guard let range = trimmed.range(of: "\": ") else { continue }
            keys.append(String(trimmed[trimmed.startIndex..<range.lowerBound].dropFirst()))
        }
        XCTAssertFalse(keys.isEmpty, "the table must be parsed, not silently seen as empty")
        XCTAssertEqual(keys.count, Set(keys).count,
                       "duplicate keys crash the process: \(keys.count) keys, "
                       + "\(Set(keys).count) unique")
    }

    /// A configuration written before the setting existed must still decode.
    func testOlderConfigurationWithoutALanguageStillLoads() throws {
        let json = #"{"schemaVersion":1,"providers":[]}"#
        let configuration = try JSONDecoder().decode(
            CodexBridgerConfiguration.self, from: Data(json.utf8)
        )
        XCTAssertEqual(configuration.interfaceLanguage, .system)
    }

    /// The setting round-trips through the stored file.
    func testLanguageRoundTripsThroughEncoding() throws {
        var configuration = CodexBridgerConfiguration()
        configuration.interfaceLanguage = .english
        let data = try JSONEncoder().encode(configuration)
        let restored = try JSONDecoder().decode(CodexBridgerConfiguration.self, from: data)
        XCTAssertEqual(restored.interfaceLanguage, .english)
    }
}