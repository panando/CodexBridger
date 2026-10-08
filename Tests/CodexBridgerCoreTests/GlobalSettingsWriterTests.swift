import XCTest
@testable import CodexBridgerCore

/// Seam: `GlobalSettingsWriter` is the only thing that may change a non-provider key in
/// config.toml. The tests are about bytes: what changed, what must not have changed, and what
/// happens when somebody else changed the file first.
final class GlobalSettingsWriterTests: XCTestCase {

    /// A file shaped like the real one: top-level keys, then the tables the user owns, then our
    /// own provider table. Every byte outside a changed key has to survive.
    static let fixture = """
    approval_policy = \"on-request\"
    approvals_reviewer = \"auto_review\"
    model = \"deepseek-v4.1-flash\"
    model_provider = \"cpa\"
    model_reasoning_effort = \"high\"
    personality = 'pragmatic'
    sandbox_mode = 'workspace-write'
    
    [desktop]
    appearanceTheme = \"dark\"
    
    [mcp_servers.exa.env]
    EXA_API_KEY = \"a-secret-that-must-survive\"
    
    [[skills.config]]
    enabled = false
    path = '/Users/x/skills/a/SKILL.md'
    
    [model_providers.cpa]
    name = \"cpa\"
    base_url = \"http://127.0.0.1:8317/v1\"
    wire_api = \"responses\"
    """

    /// Writes text to the codex home, creating it if needed.
    private func seed(_ text: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    private func seeded() throws -> (writer: GlobalSettingsWriter, paths: CodexPaths, root: URL) {
        let home = try TestSupport.makeTemporaryCodexHome()
        try seed(Self.fixture, at: home.paths.configTOML)
        let writer = GlobalSettingsWriter(paths: home.paths)
        return (writer, home.paths, home.root)
    }

    private func draft(from paths: CodexPaths) throws -> GlobalSettingsDraft {
        GlobalSettingsDraft(loaded: GlobalSettingsReader.states(
            in: try String(contentsOf: paths.configTOML, encoding: .utf8)
        ))
    }

    func testOnlyTheChangedKeyChangesAndEverythingElseIsByteIdentical() throws {
        let (writer, paths, _) = try seeded()
        var draft = try draft(from: paths)
        draft.set(.choice("never"), for: "approval_policy")

        let result = try writer.write(draft)

        XCTAssertEqual(result.writtenKeys, ["approval_policy"])
        let expected = Self.fixture.replacingOccurrences(
            of: "approval_policy = \"on-request\"",
            with: "approval_policy = \"never\""
        )
        XCTAssertEqual(result.configTOML, expected)
        XCTAssertEqual(try String(contentsOf: paths.configTOML, encoding: .utf8), expected)
    }

    func testTheBackupHoldsTheFileExactlyAsItWasBeforeTheWrite() throws {
        let (writer, paths, _) = try seeded()
        var draft = try draft(from: paths)
        draft.set(.choice("never"), for: "approval_policy")

        let result = try writer.write(draft)

        let backup = try XCTUnwrap(result.backupURL)
        XCTAssertEqual(backup.deletingLastPathComponent(), paths.backupDirectory)
        XCTAssertTrue(
            backup.lastPathComponent.hasPrefix("config-settings-"),
            "the backup names what changed: " + backup.lastPathComponent
        )
        XCTAssertTrue(backup.lastPathComponent.hasSuffix("-bak.toml"))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), Self.fixture)
    }

    func testAKeyChangedBySomebodyElseStopsTheWriteAndTouchesNothing() throws {
        let (writer, paths, _) = try seeded()
        var draft = try draft(from: paths)
        draft.set(.choice("danger-full-access"), for: "sandbox_mode")

        // Somebody else edits the same key: same meaning, different bytes.
        let external = Self.fixture.replacingOccurrences(
            of: "sandbox_mode = 'workspace-write'",
            with: "sandbox_mode = 'read-only'"
        )
        try seed(external, at: paths.configTOML)

        XCTAssertThrowsError(try writer.write(draft)) { error in
            guard case let GlobalSettingsWriteError.conflictingKeys(conflicts) = error else {
                return XCTFail("expected a conflict, got " + String(describing: error))
            }
            XCTAssertEqual(conflicts.count, 1)
            XCTAssertEqual(conflicts.first?.key, "sandbox_mode")
            XCTAssertEqual(conflicts.first?.loadedRaw, "'workspace-write'")
            XCTAssertEqual(conflicts.first?.currentRaw, "'read-only'")
        }
        XCTAssertEqual(
            try String(contentsOf: paths.configTOML, encoding: .utf8),
            external,
            "a refused write must not touch the file"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.backupDirectory.path),
            "a refused write must not leave a backup behind"
        )
    }

    /// The two value shapes the screen can still produce, each written in its own form.
    ///
    /// Numbers, free text and arrays used to be covered here too, through keys that were on the
    /// page. Those keys left on 2026-10-08 and the page now has switches and dropdowns only, so
    /// that serialisation is covered where it actually lives: `TOMLValueWriter` in
    /// TOMLDocumentTests. Keeping a catalog key around purely to test a shape would have been
    /// the tail wagging the dog.
    func testTheValueShapesTheScreenProducesAreWrittenInTheirOwnForm() throws {
        let shapes: [(SettingValue, String)] = [
            (.flag(true), "allow_login_shell = true"),
            (.choice("never"), "approval_policy = \"never\""),
        ]
        for (value, expected) in shapes {
            let (writer, paths, _) = try seeded()
            var draft = try draft(from: paths)
            let key = value == .flag(true) ? "allow_login_shell" : "approval_policy"
            draft.set(value, for: key)

            let result = try writer.write(draft)

            XCTAssertTrue(
                result.configTOML.contains(expected),
                "expected " + expected + " for " + key + ", got: " + result.configTOML
            )
        }
    }

    func testClearingAKeyRemovesItsLineAndNothingElse() throws {
        let (writer, paths, _) = try seeded()
        var draft = try draft(from: paths)
        draft.clear("sandbox_mode")

        let result = try writer.write(draft)

        let expected = Self.fixture.replacingOccurrences(of: "sandbox_mode = 'workspace-write'\n", with: "")
        XCTAssertEqual(result.configTOML, expected)
        XCTAssertTrue(result.configTOML.contains("[model_providers.cpa]"), "the provider table survives")
    }

    func testNothingChangedWritesNothingAndLeavesNoBackup() throws {
        let (writer, paths, _) = try seeded()
        let draft = try draft(from: paths)

        let result = try writer.write(draft)

        XCTAssertTrue(result.writtenKeys.isEmpty)
        XCTAssertNil(result.backupURL)
        XCTAssertEqual(try String(contentsOf: paths.configTOML, encoding: .utf8), Self.fixture)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.backupDirectory.path),
            "no change means no backup was needed"
        )
    }

    func testAConflictTheUserAcceptedIsWrittenAndBacksUpTheOtherVersionsBytes() throws {
        let (writer, paths, _) = try seeded()
        var draft = try draft(from: paths)
        draft.set(.choice("never"), for: "approval_policy")

        let external = Self.fixture.replacingOccurrences(
            of: "approval_policy = \"on-request\"",
            with: "approval_policy = 'never'"
        )
        try seed(external, at: paths.configTOML)

        let result = try writer.write(draft, acceptingConflicts: true)

        XCTAssertEqual(result.writtenKeys, ["approval_policy"])
        let backup = try XCTUnwrap(result.backupURL)
        XCTAssertEqual(
            try String(contentsOf: backup, encoding: .utf8),
            external,
            "the backup holds what was on disk, not what we loaded"
        )
        XCTAssertEqual(
            try String(contentsOf: paths.configTOML, encoding: .utf8),
            Self.fixture.replacingOccurrences(
                of: "approval_policy = \"on-request\"",
                with: "approval_policy = \"never\""
            )
        )
    }

    /// A write that silently does not land must be reported, not claimed as success.
    func testAWriteThatDoesNotLandIsReportedInsteadOfClaimedAsSuccess() throws {
        let home = try TestSupport.makeTemporaryCodexHome()
        try seed(Self.fixture, at: home.paths.configTOML)
        let writer = GlobalSettingsWriter(
            paths: home.paths,
            fileManager: .default,
            now: Date.init,
            writeFile: { _, url, _ in try FileManager.default.removeItem(at: url) }
        )
        var draft = try draft(from: home.paths)
        draft.set(.choice("never"), for: "approval_policy")

        XCTAssertThrowsError(try writer.write(draft)) { error in
            guard case let GlobalSettingsWriteError.verificationFailed(key, _, _) = error else {
                return XCTFail("expected a verification failure, got " + String(describing: error))
            }
            XCTAssertEqual(key, "approval_policy")
        }
    }

    func testAKeyChangedBySomebodyElseIsVisibleBeforeWriting() throws {
        let (writer, paths, _) = try seeded()
        var draft = try draft(from: paths)
        draft.set(.choice("never"), for: "approval_policy")
        XCTAssertEqual(writer.conflicts(for: draft), [])

        let external = Self.fixture.replacingOccurrences(
            of: "approval_policy = \"on-request\"",
            with: "approval_policy = 'on-request'"
        )
        try seed(external, at: paths.configTOML)
        XCTAssertEqual(writer.conflicts(for: draft).map(\.key), ["approval_policy"])
    }

    /// The screen knows only some of the keys a real file holds, and a newer Codex may add more.
    /// Everything it does not know has to come back out exactly as it went in.
    func testKeysThisScreenDoesNotKnowAreLeftExactlyAsTheyAre() throws {
        let text = """
        approval_policy = "on-request"
        future_key_this_build_does_not_know = "keep me"
        another_unknown = 42
        unknown_list = [
          "a",
          "b",
        ]

        [unknown_table]
        key = 'value'
        """
        let home = try TestSupport.makeTemporaryCodexHome()
        try seed(text, at: home.paths.configTOML)
        let writer = GlobalSettingsWriter(paths: home.paths)
        var draft = try draft(from: home.paths)
        draft.set(.choice("never"), for: "approval_policy")

        _ = try writer.write(draft)

        XCTAssertEqual(
            try String(contentsOf: home.paths.configTOML, encoding: .utf8),
            text.replacingOccurrences(
                of: "approval_policy = \"on-request\"",
                with: "approval_policy = \"never\""
            ),
            "only the one line may differ; every key this screen does not know must survive"
        )
    }
}
