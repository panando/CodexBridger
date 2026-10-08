import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: what 保存 and 启用 each write, and what the button does afterwards.
///
/// The user restated the contract on 2026-10-08: 保存 keeps the app's own settings and touches
/// nothing ChatGPT reads, while 启用 applies the saved provider and backs the previous files up.
/// Before that, saving a provider also rewrote its model parameter file and posted notices about
/// it — the two actions were entangled, so "saved" and "in effect" could differ without the
/// screen being able to say so.
@MainActor
final class SaveAndActivateContractTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("save-contract-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    private func readyModel() throws -> AppModel {
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        model.createProvider(from: preset)
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft())
        return model
    }

    private func filesChatGPTReads(_ model: AppModel) -> [String: Data?] {
        let catalog = paths.catalog(for: model.configuration.providers[0].id)
        return [
            "config.toml": try? Data(contentsOf: paths.configTOML),
            "auth.json": try? Data(contentsOf: paths.authJSON),
            "catalog": try? Data(contentsOf: catalog),
        ]
    }

    private func backups() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: paths.backupDirectory.path)) ?? []
    }

    /// 保存 must not touch anything ChatGPT reads, and must not take a backup.
    func testSavingWritesOnlyThisAppsOwnSettings() throws {
        let model = try readyModel()
        let before = filesChatGPTReads(model)
        XCTAssertTrue(backups().isEmpty, "a save has nothing to back up")

        // Change something a catalog write used to carry, then save.
        model.draft?.provider.baseURL = "https://changed.example.com/v1"
        model.draft?.provider.bearerToken = "sk-changed"
        XCTAssertTrue(model.saveDraft())

        XCTAssertEqual(filesChatGPTReads(model)["config.toml"] ?? nil, before["config.toml"] ?? nil,
                       "保存 must leave config.toml alone")
        XCTAssertEqual(filesChatGPTReads(model)["auth.json"] ?? nil, before["auth.json"] ?? nil,
                       "保存 must leave auth.json alone")
        XCTAssertEqual(filesChatGPTReads(model)["catalog"] ?? nil, before["catalog"] ?? nil,
                       "保存 must leave the model parameter file alone")
        XCTAssertTrue(backups().isEmpty, "保存 must not create a backup, got \(backups())")

        // And the app's own settings did change.
        let stored = try XCTUnwrap(model.configuration.provider(id: model.draft!.original.id))
        XCTAssertEqual(stored.baseURL, "https://changed.example.com/v1")
    }

    /// 启用 applies and records what it applied, so the button can tell it is done.
    func testEnablingAppliesAndRecordsTheProvider() throws {
        let model = try readyModel()
        let provider = try XCTUnwrap(model.draft?.provider)
        XCTAssertNil(model.configuration.publishedProvider, "nothing is applied yet")

        model.activate(providerID: provider.id, modelID: try XCTUnwrap(provider.models.first).id)
        waitForActivationToEnd(model)

        XCTAssertEqual(
            model.configuration.publishedProvider?.id, provider.id,
            "the applied provider must be recorded, or the button cannot know it is done"
        )
        XCTAssertTrue(
            model.configuration.publishedProvider?.hasSameAppliedState(as: provider) ?? false,
            "and recorded as applied"
        )
    }

    /// The rule the button itself follows: applied and unchanged means nothing left to do.
    func testTheButtonReportsNothingToApplyAfterEnablingAndSomethingAfterASave() throws {
        let model = try readyModel()
        let provider = try XCTUnwrap(model.draft?.provider)
        model.activate(providerID: provider.id, modelID: try XCTUnwrap(provider.models.first).id)
        waitForActivationToEnd(model)

        func availability() -> ActivationAction.Availability {
            let published = model.configuration.publishedProvider
            let current = model.draft!.provider
            return ActivationAction.availability(
                hasModels: !current.models.isEmpty,
                isDirty: model.draft!.isDirty,
                hasErrors: !model.draft!.errors.isEmpty,
                isAlreadyActive: model.configuration.activeProviderID == current.id,
                isAlreadyPublished: published?.hasSameAppliedState(as: current) ?? false
            )
        }

        XCTAssertFalse(availability().isEnabled, "just applied: nothing left to do")

        // A saved change brings it back.
        model.draft?.provider.baseURL = "https://changed.example.com/v1"
        XCTAssertTrue(model.saveDraft())
        XCTAssertTrue(availability().isEnabled, "a saved change has to be applicable")
    }

    private func waitForActivationToEnd(_ model: AppModel) {
        let deadline = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
