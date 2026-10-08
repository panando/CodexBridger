import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: the global settings screen as the window drives it.
///
/// The rules that matter are the ones a person would notice: what the rows show, when the file
/// is written, and what happens when somebody else got there first.
@MainActor
final class GlobalSettingsModelTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    static let fixture = """
    approval_policy = "on-request"
    personality = 'pragmatic'
    sandbox_mode = 'workspace-write'
    
    [model_providers.cpa]
    name = "cpa"
    base_url = "http://127.0.0.1:8317/v1"
    """

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("global-settings-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    private func seed(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: paths.codexHome, withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: paths.configTOML)
    }

    private func model(_ text: String = fixture) throws -> AppModel {
        try seed(text)
        let model = AppModel(paths: paths)
        model.loadGlobalSettings()
        return model
    }

    func testOpeningTheScreenShowsWhatTheFileHolds() throws {
        let model = try model()
        XCTAssertEqual(
            model.globalSettingsStates["approval_policy"],
            .value(raw: "\"on-request\"", parsed: .choice("on-request"))
        )
        XCTAssertEqual(model.globalSettingsStates["show_raw_agent_reasoning"], .unset)
        XCTAssertFalse(model.globalSettingsIsDirty)
    }

    func testChangingARowMakesTheScreenDirty() throws {
        let model = try model()
        model.setGlobalSetting(.choice("never"), for: "approval_policy")
        XCTAssertTrue(model.globalSettingsIsDirty)
        XCTAssertEqual(model.globalSettingPendingChange(for: "approval_policy"), .write(.choice("never")))
    }

    func testUpdatingWritesTheChangeAndNamesTheBackupFile() throws {
        let model = try model()
        model.setGlobalSetting(.choice("never"), for: "approval_policy")

        model.updateGlobalConfiguration()

        XCTAssertEqual(
            try String(contentsOf: paths.configTOML, encoding: .utf8),
            Self.fixture.replacingOccurrences(
                of: "approval_policy = \"on-request\"",
                with: "approval_policy = \"never\""
            )
        )
        XCTAssertEqual(model.globalSettingsNotice?.kind, .success)
        XCTAssertTrue(
            model.globalSettingsNotice?.message.contains("config-settings-") == true,
            "the notice names the backup: " + (model.globalSettingsNotice?.message ?? "")
        )
        XCTAssertFalse(model.globalSettingsIsDirty, "the screen shows the file it just wrote")
    }

    func testAChangeBySomebodyElseIsSurfacedAndNothingIsWritten() throws {
        let model = try model()
        model.setGlobalSetting(.choice("danger-full-access"), for: "sandbox_mode")
        let external = Self.fixture.replacingOccurrences(
            of: "sandbox_mode = 'workspace-write'",
            with: "sandbox_mode = 'read-only'"
        )
        try seed(external)

        model.updateGlobalConfiguration()

        XCTAssertEqual(model.globalSettingsConflicts.map(\.key), ["sandbox_mode"])
        XCTAssertEqual(model.globalSettingsNotice?.kind, .warning)
        XCTAssertEqual(try String(contentsOf: paths.configTOML, encoding: .utf8), external)
    }

    func testAcceptingTheConflictWritesTheUsersValue() throws {
        let model = try model()
        model.setGlobalSetting(.choice("danger-full-access"), for: "sandbox_mode")
        let external = Self.fixture.replacingOccurrences(
            of: "sandbox_mode = 'workspace-write'",
            with: "sandbox_mode = 'read-only'"
        )
        try seed(external)
        model.updateGlobalConfiguration()

        model.updateGlobalConfiguration(acceptingConflicts: true)

        XCTAssertTrue(model.globalSettingsConflicts.isEmpty)
        XCTAssertEqual(model.globalSettingsNotice?.kind, .success)
        let written = try String(contentsOf: paths.configTOML, encoding: .utf8)
        XCTAssertTrue(written.contains("sandbox_mode = \"danger-full-access\""))
    }

    func testDroppingTheConflictingKeyStillWritesTheRest() throws {
        let model = try model()
        model.setGlobalSetting(.choice("danger-full-access"), for: "sandbox_mode")
        model.setGlobalSetting(.choice("never"), for: "approval_policy")
        try seed(Self.fixture.replacingOccurrences(
            of: "sandbox_mode = 'workspace-write'",
            with: "sandbox_mode = 'read-only'"
        ))
        model.updateGlobalConfiguration()

        model.dropConflictingChanges()

        let written = try String(contentsOf: paths.configTOML, encoding: .utf8)
        XCTAssertTrue(written.contains("approval_policy = \"never\""), "the other change went through")
        XCTAssertTrue(written.contains("sandbox_mode = 'read-only'"), "the other program's value is kept")
        XCTAssertTrue(model.globalSettingsConflicts.isEmpty)
    }

    func testResetDropsEveryPendingEdit() throws {
        let model = try model()
        model.setGlobalSetting(.choice("never"), for: "approval_policy")
        model.resetGlobalSettings()
        XCTAssertFalse(model.globalSettingsIsDirty)
        XCTAssertEqual(try String(contentsOf: paths.configTOML, encoding: .utf8), Self.fixture)
    }

    /// The notice follows the interface language, and its placeholders are substituted rather than
    /// left in the sentence.
    func testTheNoticeReadsInTheInterfaceLanguage() throws {
        let model = try model()
        model.setLanguage(.english)
        model.setGlobalSetting(.choice("never"), for: "approval_policy")

        model.updateGlobalConfiguration()

        let message = try XCTUnwrap(model.globalSettingsNotice?.message)
        XCTAssertTrue(message.contains("Updated 1 setting"), message)
        XCTAssertTrue(message.contains("config-settings-"), message)
        XCTAssertFalse(message.contains("{"), "a placeholder was left in: " + message)
        XCTAssertFalse(message.contains("已更新"), "the notice is still Chinese: " + message)
    }

    /// English says "1 setting" and "2 settings", so the count has to pick the sentence.
    func testTheNoticeUsesThePluralSentenceForMoreThanOneChange() throws {
        let model = try model()
        model.setLanguage(.english)
        model.setGlobalSetting(.choice("never"), for: "approval_policy")
        model.setGlobalSetting(.choice("read-only"), for: "sandbox_mode")

        model.updateGlobalConfiguration()

        let message = try XCTUnwrap(model.globalSettingsNotice?.message)
        XCTAssertTrue(message.contains("Updated 2 settings"), message)
        XCTAssertFalse(message.contains("{"), "a placeholder was left in: " + message)
    }

    func testUpdatingWithNothingPendingWritesNothing() throws {
        let model = try model()
        model.updateGlobalConfiguration()
        XCTAssertEqual(try String(contentsOf: paths.configTOML, encoding: .utf8), Self.fixture)
        XCTAssertEqual(model.globalSettingsNotice?.kind, .success)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.backupDirectory.path),
            "nothing changed, so nothing was backed up"
        )
    }
}
