import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: editing a model parameter in place must mark the draft unsaved.
///
/// Reported from the running app: changing a model parameter (priority) left the Save button
/// disabled, so the edit could never be written. This walks the same path the inline controls
/// use — mutate the model inside the draft, then ask whether there is anything to save.
@MainActor
final class ModelParameterEditTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("model-edit-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    func testEditingAModelParameterMakesTheDraftSavable() throws {
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        model.createProvider(from: preset)
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft(), "baseline: the preset saves cleanly")
        XCTAssertFalse(model.hasUnsavedEdits)

        let target = try XCTUnwrap(model.draft?.provider.models.first)
        let originalPriority = target.priority

        // What the inline priority field does: write through into the draft.
        var draft = try XCTUnwrap(model.draft)
        let index = try XCTUnwrap(draft.provider.models.firstIndex { $0.id == target.id })
        draft.provider.models[index].priority = originalPriority + 1
        model.draft = draft

        XCTAssertTrue(
            model.hasUnsavedEdits,
            "changing a model parameter must leave unsaved work"
        )
        XCTAssertTrue(model.saveDraft(), "and it must be savable")
        XCTAssertFalse(model.hasUnsavedEdits, "saving clears the dirty flag")
    }

    func testChangingReasoningLevelsAlsoMarksTheDraftDirty() throws {
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        model.createProvider(from: preset)
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft())

        var draft = try XCTUnwrap(model.draft)
        let index = 0
        draft.provider.models[index].supportedReasoningEfforts = [.low, .high]
        model.draft = draft

        XCTAssertTrue(model.hasUnsavedEdits,
                      "toggling a reasoning level must leave unsaved work")
    }

    /// The model id must be typeable, and it must be the id that reaches config.toml.
    ///
    /// Reported from the running app: the expanded model card offered 显示名称, 上下文窗口,
    /// 推理强度, 可见性 and 排序 — but no field for the model id. The slug binding was plumbed
    /// all the way into the card and then never rendered, so the id could only be inherited from
    /// a preset. A third-party provider whose real model name differs from the preset could not be
    /// entered at all, which is the one value Codex matches on.
    func testTheModelCardOffersAModelIDEntry() throws {
        let source = try String(
            contentsOf: Snapshot.packageRoot
                .appendingPathComponent("Sources/CodexBridgerUI/Components/ProviderMappingCard.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("FormRow(\"模型 ID\""),
            "the expanded model card must render a 模型 ID row"
        )
        XCTAssertTrue(
            source.contains("ValueTextField(text: slug"),
            "that row must be bound to the slug, not to the display name"
        )
    }

    func testEditingTheModelIDReachesTheActivatedConfig() throws {
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        model.createProvider(from: preset)
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft())

        var draft = try XCTUnwrap(model.draft)
        draft.provider.models[0].slug = "my-custom-model-id"
        model.draft = draft
        XCTAssertTrue(model.hasUnsavedEdits, "typing an id must leave unsaved work")
        XCTAssertTrue(model.saveDraft())

        // Codex files are written on activation, not on save.
        let target = try XCTUnwrap(model.draft?.provider.models.first)
        model.activate(providerID: draft.provider.id, modelID: target.id)

        // activate() writes from a detached task, so wait for it to land.
        let deadline = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(model.lastActivation, "activation must complete")

        let config = try String(contentsOf: paths.configTOML, encoding: .utf8)
        XCTAssertTrue(
            config.contains("model = \"my-custom-model-id\""),
            "config.toml must carry the id the user typed, not the preset value"
        )
    }
}
