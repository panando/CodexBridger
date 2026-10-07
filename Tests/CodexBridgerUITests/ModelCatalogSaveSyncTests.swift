import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: saving a provider must reach the file ChatGPT actually reads.
///
/// Reported from the running app: editing the model parameters of a provider and pressing Save
/// left `<provider>-model-catalog.json` untouched. The cause was that the only code that writes
/// that file is activation, and the Activate button was disabled precisely for the provider
/// ChatGPT was already using — so the reported situation had no reachable path at all.
///
/// These tests drive the real save path in an isolated Codex home.
@MainActor
final class ModelCatalogSaveSyncTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("catalog-sync-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    // MARK: - Helpers

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 20,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("timed out waiting for: " + description)
    }

    private func waitWhileActivating(_ model: AppModel) {
        waitUntil("activation to finish") { !model.isActivating }
        XCTAssertNotNil(model.lastActivation, "activation must complete")
    }

    private func catalogText(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// A saved-and-activated provider, which is the state the bug report describes.
    private func makeActivatedModel() throws -> (model: AppModel, provider: ProviderConfiguration) {
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        model.createProvider(from: preset)
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft(), "baseline: the preset saves cleanly")

        let provider = try XCTUnwrap(model.draft?.provider)
        let target = try XCTUnwrap(provider.models.first)
        model.activate(providerID: provider.id, modelID: target.id)
        waitWhileActivating(model)
        return (model, provider)
    }

    /// Writes a context window through the same path the model editor sheet uses.
    private func editFirstModelContextWindow(_ model: AppModel, to value: Int) throws {
        var draft = try XCTUnwrap(model.draft)
        let index = try XCTUnwrap(draft.provider.models.indices.first)
        draft.provider.models[index].contextWindow = value
        draft.provider.models[index].maxContextWindow = value
        model.draft = draft
    }

    // MARK: - The reported bug

    func testSavingTheActiveProviderRewritesItsCatalog() throws {
        let (model, provider) = try makeActivatedModel()
        let catalogURL = paths.catalog(for: provider.id)
        let before = try XCTUnwrap(catalogText(catalogURL), "activation must write the catalog")

        try editFirstModelContextWindow(model, to: 4_242)
        XCTAssertTrue(model.saveDraft(), "the edit must be savable")

        waitUntil("the catalog to carry the new context window") {
            (self.catalogText(catalogURL) ?? "").contains("4242")
        }
        let after = try XCTUnwrap(catalogText(catalogURL))
        XCTAssertNotEqual(before, after, "saving must reach the model parameter file")

        // Assert on the entry itself, not on the file as a whole: the preset ships two models and
        // only the first was edited, so the other model's window is still the preset value.
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(after.utf8)) as? [String: Any]
        )
        let models = try XCTUnwrap(payload["models"] as? [[String: Any]])
        XCTAssertEqual(models[0]["context_window"] as? Int, 4_242)
        XCTAssertEqual(models[0]["max_context_window"] as? Int, 4_242)
    }

    /// The file must not be churned for a save that does not change the catalog.
    func testSavingWithoutChangingTheModelsLeavesTheCatalogAlone() throws {
        let (model, provider) = try makeActivatedModel()
        let catalogURL = paths.catalog(for: provider.id)
        let before = try XCTUnwrap(catalogText(catalogURL))
        let stamp = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: catalogURL.path)

        XCTAssertTrue(model.saveDraft())
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        XCTAssertEqual(catalogText(catalogURL), before)
        let modified = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: catalogURL.path)[.modificationDate] as? Date
        )
        XCTAssertEqual(modified, stamp, "an unchanged catalog must not be rewritten")
        XCTAssertNil(model.catalogSyncNotice, "nothing happened, so there is nothing to report")
    }

    func testSavingAProviderThatIsNotInUseDoesNotWriteACatalog() throws {
        let (model, first) = try makeActivatedModel()
        let firstCatalog = paths.catalog(for: first.id)
        let before = try XCTUnwrap(catalogText(firstCatalog))

        let other = try XCTUnwrap(ProviderPreset.builtIn.dropFirst().first)
        model.createProvider(from: other)
        model.draft?.provider.bearerToken = "sk-second"
        XCTAssertTrue(model.saveDraft())
        let second = try XCTUnwrap(model.draft?.provider)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.catalog(for: second.id).path),
            "a provider nobody activated must not get a catalog file"
        )
        XCTAssertEqual(catalogText(firstCatalog), before, "the live catalog must be untouched")
    }

    // MARK: - Failure is reported, never silent (and never fatal)

    func testCatalogWriteFailureDoesNotFailTheSave() throws {
        let (model, provider) = try makeActivatedModel()
        let catalogURL = paths.catalog(for: provider.id)

        // Make the destination impossible to replace: a directory where the file belongs.
        try FileManager.default.removeItem(at: catalogURL)
        try FileManager.default.createDirectory(at: catalogURL, withIntermediateDirectories: true)

        try editFirstModelContextWindow(model, to: 4_242)
        XCTAssertTrue(model.saveDraft(), "the user's own input must still be saved")

        waitUntil("a failure notice") { model.catalogSyncNotice != nil }
        let notice = try XCTUnwrap(model.catalogSyncNotice)
        XCTAssertEqual(notice.kind, .failure)
        XCTAssertTrue(
            notice.message.contains("模型参数文件没更新"),
            "the notice must say what did not happen: " + notice.message
        )

        // The edit itself must be on disk, because the save succeeded.
        let reloaded = try ConfigurationStore(paths: paths).load()
        XCTAssertEqual(
            reloaded.provider(id: provider.id)?.models.first?.contextWindow,
            4_242,
            "a failed catalog write must not lose the saved configuration"
        )
    }

    // MARK: - Changes a catalog write cannot carry

    func testRenamingTheActiveProviderAsksForAnUpdate() throws {
        let (model, _) = try makeActivatedModel()
        var draft = try XCTUnwrap(model.draft)
        draft.provider.id = "renamed-provider"
        model.draft = draft

        XCTAssertTrue(model.saveDraft())
        waitUntil("a rename notice") { model.catalogSyncNotice != nil }
        let notice = try XCTUnwrap(model.catalogSyncNotice)
        XCTAssertEqual(notice.kind, .warning)
        XCTAssertTrue(
            notice.message.contains("更新配置"),
            "the user must be told what to do: " + notice.message
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.catalog(for: "renamed-provider").path),
            "no orphan catalog for a name nothing points at"
        )
    }

    func testChangingTheAddressOfTheActiveProviderAsksForAnUpdate() throws {
        let (model, _) = try makeActivatedModel()
        var draft = try XCTUnwrap(model.draft)
        draft.provider.baseURL = "https://api.changed.example/v1"
        model.draft = draft

        XCTAssertTrue(model.saveDraft())
        waitUntil("an address-change notice") { model.catalogSyncNotice != nil }
        let notice = try XCTUnwrap(model.catalogSyncNotice)
        XCTAssertEqual(notice.kind, .warning)
        XCTAssertTrue(
            notice.message.contains("更新配置"),
            "the user must be told what to do: " + notice.message
        )
    }

    /// Editing something only the catalog carries must not raise the address/credential warning.
    func testEditingAModelParameterDoesNotRaiseTheUpdateWarning() throws {
        let (model, _) = try makeActivatedModel()
        try editFirstModelContextWindow(model, to: 4_242)

        XCTAssertTrue(model.saveDraft())
        waitUntil("the catalog to be rewritten") {
            (self.model(self.paths, model) ?? "").contains("4242")
        }
        XCTAssertNotEqual(model.catalogSyncNotice?.kind, .warning)
    }

    private func model(_ paths: CodexPaths, _ model: AppModel) -> String? {
        guard let id = model.configuration.activeProviderID else { return nil }
        return catalogText(paths.catalog(for: id))
    }

    // MARK: - What counts as a published setting

    func testPublishedSettingsIgnoreTheModelListAndTheIdentifier() {
        let base = ProviderConfiguration(
            id: "demo",
            name: "Demo",
            baseURL: "https://api.example.com/v1",
            credentialMode: .bearerToken,
            bearerToken: "sk-one",
            models: [ModelConfiguration(slug: "a", displayName: "A")]
        )

        var withAnotherModel = base
        withAnotherModel.models = [ModelConfiguration(slug: "b", displayName: "B")]
        XCTAssertTrue(
            base.hasSamePublishedSettings(as: withAnotherModel),
            "the model list reaches the catalog, not config.toml"
        )

        var renamed = base
        renamed.id = "other"
        XCTAssertTrue(base.hasSamePublishedSettings(as: renamed), "the id is checked separately")

        var recategorised = base
        recategorised.category = "别的分组"
        XCTAssertTrue(base.hasSamePublishedSettings(as: recategorised), "category is our own metadata")

        for mutate in [
            { (p: inout ProviderConfiguration) in p.name = "Changed" },
            { (p: inout ProviderConfiguration) in p.baseURL = "https://other.example/v1" },
            { (p: inout ProviderConfiguration) in p.bearerToken = "sk-two" },
            { (p: inout ProviderConfiguration) in p.requiresOpenAIAuth = true },
            { (p: inout ProviderConfiguration) in p.queryParams = ["a": "b"] },
            { (p: inout ProviderConfiguration) in p.httpHeaders = ["X": "Y"] },
            { (p: inout ProviderConfiguration) in p.requestMaxRetries = 9 },
            { (p: inout ProviderConfiguration) in p.supportsWebsockets = true }
        ] {
            var changed = base
            mutate(&changed)
            XCTAssertFalse(
                base.hasSamePublishedSettings(as: changed),
                "every published setting must be noticed"
            )
        }
    }
}
