import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: applying an imported model catalog to the form.
///
/// Importing is how a user reuses a model list they already have instead of retyping it. The
/// contract: it edits the draft and nothing else, it never produces two models with the same id,
/// and it never disturbs a model the user did not ask to replace.
@MainActor
final class ModelCatalogImportTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("catalog-import-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    // MARK: - Fixtures

    private func outcome(_ entries: [[String: Any]]) throws -> ModelCatalogImporter.ImportOutcome {
        let data = try JSONSerialization.data(withJSONObject: ["models": entries])
        return try ModelCatalogImporter.parse(data: data)
    }

    private func entry(slug: String, contextWindow: Int = 200_000) -> [String: Any] {
        [
            "slug": slug,
            "display_name": slug.uppercased(),
            "description": "imported " + slug,
            "context_window": contextWindow,
            "max_context_window": contextWindow,
            "supported_reasoning_levels": [["effort": "low"], ["effort": "high"]],
            "default_reasoning_level": "high",
            "visibility": "list",
            "priority": 1_000
        ]
    }

    /// A model-editing session: a saved provider open in the form.
    private func makeEditingModel() throws -> AppModel {
        let model = AppModel(paths: paths)
        model.load()
        model.createProvider(from: try XCTUnwrap(ProviderPreset.builtIn.first))
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft())
        return model
    }

    private func slugs(_ model: AppModel) -> [String] {
        (model.draft?.provider.models ?? []).map(\.slug)
    }

    // MARK: - Importing into the provider being edited

    func testImportingAddsTheSelectedModelsToTheDraft() throws {
        let model = try makeEditingModel()
        let before = slugs(model)
        let parsed = try outcome([entry(slug: "new-one"), entry(slug: "new-two")])

        model.beginCatalogImport(.draftProvider)
        let merge = try XCTUnwrap(
            model.applyCatalogImport(parsed, slugs: ["new-one", "new-two"])
        )

        XCTAssertEqual(merge.added, ["new-one", "new-two"])
        XCTAssertEqual(slugs(model), before + ["new-one", "new-two"])
        XCTAssertTrue(model.hasUnsavedEdits, "an import is unsaved work")
        XCTAssertNil(model.catalogImportRequest, "the request is consumed")
    }

    func testImportingOnlyAddsTheSelectedModels() throws {
        let model = try makeEditingModel()
        let before = slugs(model)
        let parsed = try outcome([entry(slug: "wanted"), entry(slug: "unwanted")])

        model.beginCatalogImport(.draftProvider)
        _ = model.applyCatalogImport(parsed, slugs: ["wanted"])

        XCTAssertEqual(slugs(model), before + ["wanted"])
        XCTAssertFalse(slugs(model).contains("unwanted"))
    }

    func testImportingOverwritesASameNamedModelAndKeepsItsIdentity() throws {
        let model = try makeEditingModel()
        let existing = try XCTUnwrap(model.draft?.provider.models.first)
        let countBefore = try XCTUnwrap(model.draft?.provider.models.count)
        let parsed = try outcome([entry(slug: existing.slug, contextWindow: 4_242)])

        model.beginCatalogImport(.draftProvider)
        let merge = try XCTUnwrap(model.applyCatalogImport(parsed, slugs: [existing.slug]))

        XCTAssertEqual(merge.added, [])
        XCTAssertEqual(merge.overwritten, [existing.slug])
        XCTAssertEqual(
            model.draft?.provider.models.count, countBefore,
            "an overwrite must not add a model"
        )
        let replaced = try XCTUnwrap(model.draft?.provider.models.first)
        XCTAssertEqual(replaced.id, existing.id, "the card must not jump to a new identity")
        XCTAssertEqual(replaced.contextWindow, 4_242, "the file's values win")
    }

    func testImportingWritesNothingToDiskUntilSaved() throws {
        let model = try makeEditingModel()
        let savedBefore = try ConfigurationStore(paths: paths).load()
        let parsed = try outcome([entry(slug: "draft-only")])

        model.beginCatalogImport(.draftProvider)
        _ = model.applyCatalogImport(parsed, slugs: ["draft-only"])

        let savedAfter = try ConfigurationStore(paths: paths).load()
        XCTAssertEqual(savedAfter.providers.count, savedBefore.providers.count)
        XCTAssertFalse(
            (savedAfter.provider(id: try XCTUnwrap(savedBefore.providers.first).id)?
                .models.contains { $0.slug == "draft-only" }) ?? true,
            "the import must stay in the draft until Save"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: paths.appConfiguration.path),
            "but the previously saved configuration is still there"
        )
    }

    func testAnEmptySelectionDoesNothing() throws {
        let model = try makeEditingModel()
        let before = slugs(model)
        let parsed = try outcome([entry(slug: "ignored")])

        model.beginCatalogImport(.draftProvider)
        XCTAssertNil(model.applyCatalogImport(parsed, slugs: []))
        XCTAssertEqual(slugs(model), before)
        XCTAssertNotNil(model.catalogImportRequest, "a request with nothing applied stays open")
    }

    // MARK: - Creating a provider from a file

    func testCreatingAProviderFromACatalogPrefillsOnlyTheModels() throws {
        let model = try makeEditingModel()
        let parsed = try outcome([entry(slug: "from-file-1"), entry(slug: "from-file-2")])

        model.beginCatalogImport(.newProvider)
        let merge = try XCTUnwrap(model.applyCatalogImport(parsed, slugs: ["from-file-1", "from-file-2"]))

        XCTAssertEqual(merge.added.count, 2)
        let created = try XCTUnwrap(model.draft?.provider)
        XCTAssertEqual(created.models.map(\.slug), ["from-file-1", "from-file-2"])
        XCTAssertTrue(created.baseURL.isEmpty, "a catalog carries no address")
        XCTAssertTrue(created.bearerToken.isEmpty, "and no credential")
        XCTAssertEqual(created.name, "新提供商")
        XCTAssertEqual(model.selectedProviderID, created.id)
        XCTAssertTrue(model.draft?.isNew ?? false, "it is a new, unsaved provider")
    }

    func testTheImportedProviderIsSavableOnceItHasAnAddress() throws {
        let model = try makeEditingModel()
        let parsed = try outcome([entry(slug: "one")])

        model.beginCatalogImport(.newProvider)
        _ = model.applyCatalogImport(parsed, slugs: ["one"])
        model.draft?.provider.baseURL = "https://api.example.com/v1"
        model.draft?.provider.bearerToken = "sk-new"

        XCTAssertTrue(model.saveDraft(), "the imported models must pass validation")
        XCTAssertEqual(
            try ConfigurationStore(paths: paths).load().providers.last?.models.map(\.slug),
            ["one"]
        )
    }

    func testEveryImportedModelSurvivesTheFormValidation() throws {
        let model = try makeEditingModel()
        // A file with everything missing that can be missing.
        var bare = entry(slug: "bare")
        for key in ["display_name", "description", "context_window", "max_context_window",
                    "supported_reasoning_levels", "default_reasoning_level", "visibility"] {
            bare.removeValue(forKey: key)
        }
        let parsed = try outcome([bare, entry(slug: "small", contextWindow: 512)])

        model.beginCatalogImport(.draftProvider)
        _ = model.applyCatalogImport(parsed, slugs: ["bare", "small"])

        XCTAssertEqual(
            model.draft?.errors.count, 0,
            "imported models must not grey out Save: "
                + (model.draft?.errors.map { $0.message }.joined(separator: "; ") ?? "")
        )
        model.draft?.provider.baseURL = "https://api.example.com/v1"
        XCTAssertTrue(model.saveDraft())
    }
}
