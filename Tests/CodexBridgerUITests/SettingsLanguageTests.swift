import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: the language choice from the Settings window.
@MainActor
final class SettingsLanguageTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lang-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    /// The point of the setting: the interface language changes.
    func testChoosingEnglishChangesWhatTheInterfaceResolves() throws {
        let model = AppModel(paths: paths)
        XCTAssertEqual(model.t("保存"), "保存", "Chinese is the source language")
        model.setLanguage(.english)
        XCTAssertEqual(model.t("保存"), "Save")
        XCTAssertEqual(model.t("模型提供商"), "Providers")
    }

    /// And survives a restart, which is what makes it a setting rather than a toggle.
    func testTheChoiceSurvivesARestart() throws {
        let first = AppModel(paths: paths)
        first.setLanguage(.english)

        let reopened = AppModel(paths: paths)
        XCTAssertEqual(reopened.configuration.interfaceLanguage, .english)
        XCTAssertEqual(reopened.t("设置"), "Settings")
    }

    func testSwitchingBackToChineseIsAlsoStored() throws {
        let model = AppModel(paths: paths)
        model.setLanguage(.english)
        model.setLanguage(.chinese)
        XCTAssertEqual(AppModel(paths: paths).configuration.interfaceLanguage, .chinese)
        XCTAssertEqual(model.resolvedLanguage, .chinese)
    }

    /// An untranslated string must still read correctly rather than show a key.
    func testAnUntranslatedStringStillReadsInEnglish() throws {
        let model = AppModel(paths: paths)
        model.setLanguage(.english)
        XCTAssertEqual(model.t("这一句还没有翻译"), "这一句还没有翻译")
    }
}