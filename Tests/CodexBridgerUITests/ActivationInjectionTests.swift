import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: clicking 启用 must actually write the Codex files.
///
/// Reported from the running app: pressing 启用 did nothing at all — no files, no message.
/// The cause was not in the writer. `requestActivation` re-read what Codex has on disk and, when
/// the current `model_provider` is one this app does not manage, it stops and sets
/// `pendingActivation` for a confirmation. Nothing in the UI ever read that value, so the prompt
/// never appeared and the activation never ran. The isolated test home looked healthy because an
/// empty Codex home has no foreign provider, so it took the branch that always worked.
///
/// These tests drive the real path with a foreign config present.
@MainActor
final class ActivationInjectionTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("activation-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    /// A config this app did not write: an unrelated provider id pointing somewhere else.
    private func writeForeignCodexConfig() throws {
        let foreignConfig = """
            model_provider = "someone-elses-provider"
            model = "their-model"

            [model_providers.someone-elses-provider]
            name = "Hand written"
            base_url = "https://example.invalid/v1"
            """
        try AtomicFile.write(foreignConfig + "\n", to: paths.configTOML)
        try AtomicFile.write(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-foreign"}"#, to: paths.authJSON)
    }

    private func makeReadyModel() throws -> AppModel {
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        model.createProvider(from: preset)
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft())
        return model
    }

    func testForeignConfigIsBackedUpBeforeWeReplaceIt() throws {
        let model = try makeReadyModel()
        try writeForeignCodexConfig()

        let provider = try XCTUnwrap(model.draft?.provider)
        let target = try XCTUnwrap(provider.models.first)
        model.requestActivation(providerID: provider.id, modelID: target.id)

        // It must not write straight over a config it does not own.
        XCTAssertNotNil(model.pendingActivation, "a foreign config must be confirmed first")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.catalog(for: provider.id).path),
                       "nothing may be written before the user confirms")

        model.confirmPendingActivation()
        let deadline = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        // The foreign files must be recoverable.
        let backups = try FileManager.default.contentsOfDirectory(atPath: paths.backupDirectory.path)
        XCTAssertTrue(backups.contains { $0.hasPrefix("config-") && $0.hasSuffix("-bak.toml") },
                      "the replaced config.toml must be backed up, got \(backups)")
        XCTAssertTrue(backups.contains { $0.hasPrefix("auth-") && $0.hasSuffix("-bak.json") },
                      "the replaced auth.json must be backed up, got \(backups)")
    }

    /// The regression itself: without a prompt being *possible*, nothing happened at all.
    func testActivationNoLongerStallsWhenConfirming() throws {
        let model = try makeReadyModel()
        try writeForeignCodexConfig()

        let provider = try XCTUnwrap(model.draft?.provider)
        let target = try XCTUnwrap(provider.models.first)
        model.requestActivation(providerID: provider.id, modelID: target.id)
        XCTAssertNotNil(model.pendingActivation)
        model.confirmPendingActivation()
        XCTAssertNil(model.pendingActivation, "confirming must clear the pending state")

        let deadline = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(model.lastActivation, "activation must run")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.configTOML.path))
        let config = try String(contentsOf: paths.configTOML, encoding: .utf8)
        XCTAssertTrue(config.contains("model_provider = \"" + provider.id + "\""),
                      "config.toml must now point at the provider this app manages")
    }

    /// Switching between two providers this app manages is not a takeover and must not ask.
    func testSwitchingBetweenManagedProvidersDoesNotPrompt() throws {
        let model = try makeReadyModel()
        // Point Codex at the provider this app already manages, as if we had activated it.
        let provider = try XCTUnwrap(model.draft?.provider)
        try AtomicFile.write("model_provider = \"" + provider.id + "\"\n", to: paths.configTOML)

        let other = try XCTUnwrap(ProviderPreset.builtIn.dropFirst().first)
        model.createProvider(from: other)
        model.draft?.provider.bearerToken = "sk-test-2"
        XCTAssertTrue(model.saveDraft())
        let second = try XCTUnwrap(model.draft?.provider)
        let target = try XCTUnwrap(second.models.first)

        model.requestActivation(providerID: second.id, modelID: target.id)
        XCTAssertNil(model.pendingActivation,
                     "moving between our own providers must not ask for confirmation")
    }

    /// The app must show which provider is live, and that state must survive a reload.
    func testActiveProviderIsRecordedAndReloaded() throws {
        let model = try makeReadyModel()
        let provider = try XCTUnwrap(model.draft?.provider)
        let target = try XCTUnwrap(provider.models.first)
        model.activate(providerID: provider.id, modelID: target.id)
        let deadline = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(model.configuration.activeProviderID, provider.id)

        // A fresh AppModel reading the same home must recover the active provider, so the
        // indicator is not a session-only decoration.
        let reloaded = AppModel(paths: paths)
        reloaded.load()
        XCTAssertEqual(reloaded.configuration.activeProviderID, provider.id,
                       "the active provider must survive a restart")
    }

    /// Switching providers must not leave the previous one behind in config.toml.
    ///
    /// Reported from the running app with the real file: after activating DeepSeek, config.toml
    /// still carried the whole `[model_providers.cpa]` table — base_url, name, wire_api and the
    /// bearer token. Only our own table was replaced, never the others removed, so Codex kept a
    /// resolvable dead provider pointing at a service the app no longer manages.
    ///
    /// The user's own unrelated settings must survive that clean-up.
    func testActivatingAnotherProviderRemovesTheOldOneFromConfig() throws {
        let model = try makeReadyModel()

        let existing = """
            model_provider = "cpa"
            model = "some-old-model"
            model_reasoning_verbosity = "high"

            [model_providers.cpa]
            base_url = 'http://127.0.0.1:8317/v1'
            name = 'CPA'
            wire_api = 'responses'
            experimental_bearer_token = '123456'
            requires_openai_auth = true
            """
        try AtomicFile.write(existing + "\n", to: paths.configTOML)

        let provider = try XCTUnwrap(model.draft?.provider)
        let target = try XCTUnwrap(provider.models.first)
        model.activate(providerID: provider.id, modelID: target.id)
        let deadline = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let config = try String(contentsOf: paths.configTOML, encoding: .utf8)
        XCTAssertFalse(config.contains("model_providers.cpa"),
                       "the replaced provider must be gone, got:\n" + config)
        XCTAssertFalse(config.contains("127.0.0.1:8317"),
                       "the old provider address must not survive, got:\n" + config)
        XCTAssertFalse(config.contains("123456"),
                       "the old provider token must not survive, got:\n" + config)
        XCTAssertTrue(config.contains("[model_providers." + provider.id + "]"),
                      "the activated provider must be present")
        XCTAssertTrue(config.contains("model_reasoning_verbosity = \"high\""),
                      "unrelated user settings must be preserved, got:\n" + config)
    }

    /// auth.json must follow the same rule as config.toml: switching providers replaces the
    /// credential instead of merging with the old one.
    ///
    /// Reported by the user: after activating DeepSeek, auth.json still held the previous
    /// provider's key. The writer merged into the existing object, so `CPA_KEY` survived as
    /// clear text on disk for a service the app no longer manages. The provider table in
    /// config.toml had the same defect and was fixed first; the credential is the same bug.
    ///
    /// The old contents are still backed up before the write, so the key is recoverable.
    func testSwitchingProviderReplacesTheOldKeyInAuthJSON() throws {
        let model = try makeReadyModel()

        // An auth.json left behind by a different provider.
        let existing = """
            {
              "auth_mode" : "apikey",
              "CPA_KEY" : "123456",
              "SOME_OTHER_API_KEY" : "stale-value",
              "OPENAI_API_KEY" : "123456"
            }
            """
        try AtomicFile.write(existing, to: paths.authJSON)

        let provider = try XCTUnwrap(model.draft?.provider)
        let target = try XCTUnwrap(provider.models.first)
        model.activate(providerID: provider.id, modelID: target.id)
        let deadline = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let data = try Data(contentsOf: paths.authJSON)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertFalse(object.keys.contains("CPA_KEY"),
                       "the replaced provider's key must be gone, got: \(object.keys.sorted())")
        XCTAssertFalse(object.keys.contains("SOME_OTHER_API_KEY"),
                       "any other provider key must be gone, got: \(object.keys.sorted())")
        XCTAssertEqual(object["auth_mode"], "apikey", "auth_mode is structural and stays")
        XCTAssertNotNil(object["OPENAI_API_KEY"], "Codex still needs its documented key")
        XCTAssertEqual(object[provider.id.uppercased().replacingOccurrences(of: "-", with: "_") + "_KEY"],
                       provider.bearerToken, "the activated provider's key must be written")

        // And the removed key must still be recoverable from the backup.
        let backups = try FileManager.default.contentsOfDirectory(atPath: paths.backupDirectory.path)
        let authBackup = try XCTUnwrap(backups.first { $0.hasPrefix("auth-") && $0.hasSuffix("-bak.json") })
        let backupData = try Data(contentsOf: paths.backupDirectory.appendingPathComponent(authBackup))
        let backupObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: backupData) as? [String: String])
        XCTAssertEqual(backupObject["CPA_KEY"], "123456",
                       "the replaced key must be preserved in the backup")
    }

    /// Switching between providers this app manages must not keep piling up backups.
    ///
    /// Every activation used to copy the config and auth files into the backup folder, so a
    /// session flipping between two of the app's own providers filled the directory with
    /// near-identical copies of a file the app can regenerate at any time. A config naming one
    /// of our providers is reproducible, so it is skipped; the activation says so in a warning
    /// rather than doing it silently.
    func testSwitchingBetweenManagedProvidersDoesNotAccumulateBackups() throws {
        let model = try makeReadyModel()
        let first = try XCTUnwrap(model.draft?.provider)
        let firstTarget = try XCTUnwrap(first.models.first)
        model.activate(providerID: first.id, modelID: firstTarget.id)
        let deadline = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let afterFirst = (try? FileManager.default
            .contentsOfDirectory(atPath: paths.backupDirectory.path)) ?? []
        XCTAssertTrue(afterFirst.isEmpty,
                      "a fresh home has nothing to back up, got \(afterFirst)")

        // Switch to a second provider we also manage: the first config is ours, so skip it.
        let other = try XCTUnwrap(ProviderPreset.builtIn.dropFirst().first)
        model.createProvider(from: other)
        model.draft?.provider.bearerToken = "sk-second"
        XCTAssertTrue(model.saveDraft())
        let second = try XCTUnwrap(model.draft?.provider)
        let secondTarget = try XCTUnwrap(second.models.first)
        model.activate(providerID: second.id, modelID: secondTarget.id)
        let deadline2 = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline2 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let afterSecond = (try? FileManager.default
            .contentsOfDirectory(atPath: paths.backupDirectory.path)) ?? []
        XCTAssertTrue(afterSecond.isEmpty,
                      "switching between our own providers must not create backups, got \(afterSecond)")
        XCTAssertTrue(model.lastActivation?.warnings.contains { $0.contains("跳过备份") } ?? false,
                      "the skip must be reported, not silent")

        // The activation itself must still have happened.
        let config = try String(contentsOf: paths.configTOML, encoding: .utf8)
        XCTAssertTrue(config.contains("model_provider = \"" + second.id + "\""))
    }

    /// A config this app did not write is the only copy that exists, so it is still saved —
    /// and the filename says whose it was.
    func testForeignConfigIsStillBackedUpAndNamedAfterItsProvider() throws {
        let model = try makeReadyModel()
        try writeForeignCodexConfig()
        let provider = try XCTUnwrap(model.draft?.provider)
        let target = try XCTUnwrap(provider.models.first)
        model.activate(providerID: provider.id, modelID: target.id)
        let deadline = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let backups = try FileManager.default.contentsOfDirectory(atPath: paths.backupDirectory.path)
        XCTAssertTrue(
            backups.contains("config-someone-elses-provider-" + backups.first(where: { $0.hasPrefix("config-") })!.dropFirst("config-someone-elses-provider-".count)),
            "the backup must be named after the foreign provider, got \(backups)")
        XCTAssertTrue(backups.contains { $0.hasSuffix("-bak.json") && $0.contains("auth-") },
                      "auth.json must be backed up too, got \(backups)")
    }

    /// The regression guard for the wiring itself.
    ///
    /// The failure was a state with no reader: `pendingActivation` was set, the writer was
    /// correct, and every test below still passed, because the tests call
    /// `confirmPendingActivation()` directly. Only the *view* was missing. Asserting the reader
    /// exists is the only thing that catches "the state is produced but nobody consumes it".

    /// The first frame must already contain the data.
    ///
    /// Reported from the running app: the window flickered on launch and the first frame did not
    /// match the final one. The cause was that the stored configuration was read from `.task`,
    /// which runs *after* the first render, so the window could be committed with an empty
    /// sidebar and an empty detail pane. Loading moved into `init`, before any view is evaluated.
    ///
    /// This asserts the mechanism rather than the symptom: a freshly constructed model must
    /// already know its providers and which one is selected, with nobody having called load().
    func testAFreshModelAlreadyHasItsDataWithoutLoading() throws {
        let first = try makeReadyModel()
        let provider = try XCTUnwrap(first.draft?.provider)
        let target = try XCTUnwrap(provider.models.first)
        first.activate(providerID: provider.id, modelID: target.id)
        let deadline = Date().addingTimeInterval(20)
        while first.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        // Deliberately no load() call here: that is the point.
        let fresh = AppModel(paths: paths)
        XCTAssertFalse(fresh.configuration.providers.isEmpty,
                       "providers must be present before the first render")
        XCTAssertNotNil(fresh.selectedProviderID,
                        "a provider must already be selected for the first render")
        XCTAssertEqual(fresh.configuration.activeProviderID, provider.id,
                       "the active provider must be known before the first render")
        // The reported flash was the "no providers yet" screen. The detail pane shows it when the
        // draft is nil, so the draft has to exist before the first frame too — otherwise the
        // sidebar is populated but the detail pane still flashes the empty state.
        XCTAssertNotNil(fresh.draft,
                        "the editor draft must exist before the first render, or the empty "
                        + "state flashes on the detail pane")
    }

    func testSomeViewActuallyConsumesPendingActivation() throws {
        let source = try String(
            contentsOf: Snapshot.packageRoot
                .appendingPathComponent("Sources/CodexBridgerUI/ContentView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("model.pendingActivation"),
            "a view must read pendingActivation, or activation silently stops"
        )
        XCTAssertTrue(
            source.contains("model.confirmPendingActivation()"),
            "the confirmation must be reachable from the UI"
        )
        XCTAssertTrue(
            source.contains("model.cancelPendingActivation()"),
            "the user must be able to decline"
        )
    }
}