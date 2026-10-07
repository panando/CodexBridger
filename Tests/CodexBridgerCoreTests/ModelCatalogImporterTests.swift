import XCTest
@testable import CodexBridgerCore

/// Seam: ModelCatalogImporter.parse(data:) — reading an existing model catalog back in.
///
/// The file is machine-generated and not always well formed, and anything it produces must
/// survive ProviderDraft's validation, because an invalid model greys out Save and makes the
/// whole form unwritable. These tests pin the field mapping and every fallback.
final class ModelCatalogImporterTests: XCTestCase {

    // MARK: - Fixtures

    private func json(_ models: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["models": models])
    }

    /// A well-formed entry carrying the extra fields real catalogs have.
    private func fullEntry(
        slug: String = "demo-large",
        displayName: String = "Demo Large",
        description: String = "A demo model",
        contextWindow: Int = 200_000,
        maxContextWindow: Int = 200_000,
        efforts: [String] = ["low", "medium", "high"],
        defaultEffort: String = "high",
        visibility: String = "list",
        priority: Int = 1000
    ) -> [String: Any] {
        [
            "slug": slug,
            "display_name": displayName,
            "description": description,
            "context_window": contextWindow,
            "max_context_window": maxContextWindow,
            "supported_reasoning_levels": efforts.map { ["effort": $0, "description": $0] },
            "default_reasoning_level": defaultEffort,
            "visibility": visibility,
            "priority": priority,
            // Fields CodexBridger does not store. They must be ignored, never imported.
            "base_instructions": "You are Codex.",
            "shell_type": "shell_command",
            "supported_in_api": true,
            "input_modalities": ["text", "image"],
            "supports_search_tool": true,
            "truncation_policy": ["mode": "tokens", "limit": 10_000]
        ]
    }

    // MARK: - The nine fields

    func testImportsTheNineFieldsOneToOne() throws {
        let outcome = try ModelCatalogImporter.parse(data: json([fullEntry()]))

        XCTAssertEqual(outcome.models.count, 1)
        XCTAssertTrue(outcome.skipped.isEmpty)
        let model = outcome.models[0].model
        XCTAssertEqual(model.slug, "demo-large")
        XCTAssertEqual(model.displayName, "Demo Large")
        XCTAssertEqual(model.modelDescription, "A demo model")
        XCTAssertEqual(model.contextWindow, 200_000)
        XCTAssertEqual(model.maxContextWindow, 200_000)
        XCTAssertEqual(model.supportedReasoningEfforts, [.low, .medium, .high])
        XCTAssertEqual(model.defaultReasoningEffort, .high)
        XCTAssertEqual(model.visibility, .list)
        XCTAssertEqual(model.priority, 1, "priority is renumbered, not copied")
    }

    func testAWellFormedEntryProducesNoNotes() throws {
        let outcome = try ModelCatalogImporter.parse(data: json([fullEntry()]))

        XCTAssertTrue(
            outcome.models[0].notes.isEmpty,
            "nothing was substituted, so there is nothing to report: \(outcome.models[0].notes)"
        )
        XCTAssertTrue(outcome.notes.isEmpty)
    }

    func testVisibilityHideIsCarriedOver() throws {
        let outcome = try ModelCatalogImporter.parse(data: json([fullEntry(visibility: "hide")]))

        XCTAssertEqual(outcome.models[0].model.visibility, .hide)
    }

    // MARK: - Fallbacks

    func testMissingDisplayNameFallsBackToSlug() throws {
        var entry = fullEntry()
        entry.removeValue(forKey: "display_name")

        let outcome = try ModelCatalogImporter.parse(data: json([entry]))
        let imported = outcome.models[0]

        XCTAssertEqual(imported.model.displayName, "demo-large")
        XCTAssertFalse(imported.notes.isEmpty, "a substituted value must be reported")
    }

    func testMissingDescriptionFallsBackToDisplayName() throws {
        var entry = fullEntry()
        entry.removeValue(forKey: "description")

        let imported = try ModelCatalogImporter.parse(data: json([entry])).models[0]

        XCTAssertEqual(imported.model.modelDescription, "Demo Large")
        XCTAssertFalse(imported.notes.isEmpty)
    }

    func testMissingContextWindowFallsBackToTheDefault() throws {
        var entry = fullEntry()
        entry.removeValue(forKey: "context_window")
        entry.removeValue(forKey: "max_context_window")

        let imported = try ModelCatalogImporter.parse(data: json([entry])).models[0]

        XCTAssertEqual(imported.model.contextWindow, ModelCatalogGenerator.defaultContextWindow)
        XCTAssertEqual(imported.model.maxContextWindow, ModelCatalogGenerator.defaultContextWindow)
        XCTAssertFalse(imported.notes.isEmpty)
    }

    func testContextWindowBelowTheMinimumIsRaisedTo1024() throws {
        var entry = fullEntry(contextWindow: 512, maxContextWindow: 512)
        entry["context_window"] = 512
        entry["max_context_window"] = 512

        let imported = try ModelCatalogImporter.parse(data: json([entry])).models[0]

        XCTAssertEqual(imported.model.contextWindow, ProviderDraft.minimumContextWindow)
        XCTAssertEqual(imported.model.maxContextWindow, ProviderDraft.minimumContextWindow)
        XCTAssertFalse(imported.notes.isEmpty)
    }

    func testMaxContextWindowIsRaisedToContextWindow() throws {
        var entry = fullEntry(contextWindow: 200_000, maxContextWindow: 200_000)
        entry["max_context_window"] = 1_000

        let imported = try ModelCatalogImporter.parse(data: json([entry])).models[0]

        XCTAssertEqual(imported.model.contextWindow, 200_000)
        XCTAssertEqual(imported.model.maxContextWindow, 200_000)
        XCTAssertFalse(imported.notes.isEmpty)
    }

    func testOutOfRangeEffortIsDroppedAndReported() throws {
        let entry = fullEntry(efforts: ["low", "minimal", "high"], defaultEffort: "low")

        let imported = try ModelCatalogImporter.parse(data: json([entry])).models[0]

        XCTAssertEqual(imported.model.supportedReasoningEfforts, [.low, .high])
        XCTAssertTrue(
            imported.notes.contains { $0.contains("minimal") },
            "the dropped level must be named: \(imported.notes)"
        )
    }

    func testAllOutOfRangeEffortsFallBackToMedium() throws {
        let entry = fullEntry(efforts: ["minimal", "none"], defaultEffort: "minimal")

        let imported = try ModelCatalogImporter.parse(data: json([entry])).models[0]

        XCTAssertEqual(imported.model.supportedReasoningEfforts, [.medium])
        XCTAssertEqual(imported.model.defaultReasoningEffort, .medium)
        XCTAssertFalse(imported.notes.isEmpty)
    }

    func testDefaultEffortOutsideTheLevelsFallsBackToTheFirst() throws {
        let entry = fullEntry(efforts: ["low", "high"], defaultEffort: "max")

        let imported = try ModelCatalogImporter.parse(data: json([entry])).models[0]

        XCTAssertEqual(imported.model.defaultReasoningEffort, .low)
        XCTAssertFalse(imported.notes.isEmpty)
    }

    func testUnknownVisibilityFallsBackToList() throws {
        let entry = fullEntry(visibility: "sometimes")

        let imported = try ModelCatalogImporter.parse(data: json([entry])).models[0]

        XCTAssertEqual(imported.model.visibility, .list)
        XCTAssertFalse(imported.notes.isEmpty)
    }

    func testEffortOrderIsCanonicalised() throws {
        let entry = fullEntry(efforts: ["high", "low"], defaultEffort: "high")

        let imported = try ModelCatalogImporter.parse(data: json([entry])).models[0]

        XCTAssertEqual(imported.model.supportedReasoningEfforts, [.low, .high])
    }

    // MARK: - Skipping

    func testModelWithoutASlugIsSkippedAndReported() throws {
        var entry = fullEntry()
        entry.removeValue(forKey: "slug")

        let outcome = try ModelCatalogImporter.parse(
            data: json([entry, fullEntry(slug: "good")])
        )

        XCTAssertEqual(outcome.models.map(\.model.slug), ["good"])
        XCTAssertEqual(outcome.skipped.count, 1)
        XCTAssertTrue(outcome.skipped[0].reason.contains("slug"))
    }

    func testModelWithABlankSlugIsSkipped() throws {
        let outcome = try ModelCatalogImporter.parse(
            data: json([fullEntry(slug: "   "), fullEntry(slug: "good")])
        )

        XCTAssertEqual(outcome.models.map(\.model.slug), ["good"])
        XCTAssertEqual(outcome.skipped.count, 1)
    }

    func testDuplicateSlugWithinTheFileIsSkippedAndReported() throws {
        let outcome = try ModelCatalogImporter.parse(
            data: json([fullEntry(slug: "same"), fullEntry(slug: "same")])
        )

        XCTAssertEqual(outcome.models.count, 1)
        XCTAssertEqual(outcome.skipped.count, 1)
        XCTAssertEqual(outcome.skipped[0].slug, "same")
    }

    func testAllModelsSkippedIsReportedAsAnError() throws {
        var entry = fullEntry()
        entry.removeValue(forKey: "slug")

        XCTAssertThrowsError(try ModelCatalogImporter.parse(data: json([entry]))) { error in
            guard let failure = error as? ModelCatalogImporter.ImportError else {
                return XCTFail("expected an ImportError, got \(error)")
            }
            guard case let .nothingImportable(skipped) = failure else {
                return XCTFail("expected nothingImportable, got \(failure)")
            }
            XCTAssertEqual(skipped.count, 1)
        }
    }

    func testSourceModelCountReportsTheFileNotTheSurvivors() throws {
        var bad = fullEntry(slug: "bad")
        bad.removeValue(forKey: "slug")

        let outcome = try ModelCatalogImporter.parse(
            data: json([fullEntry(slug: "good"), bad])
        )

        XCTAssertEqual(outcome.sourceModelCount, 2)
        XCTAssertEqual(outcome.models.count, 1)
    }

    // MARK: - Priority

    func testPriorityIsRenumberedInFileOrder() throws {
        let entries = [
            fullEntry(slug: "a", priority: 1_000),
            fullEntry(slug: "b", priority: 1_000),
            fullEntry(slug: "c", priority: 42)
        ]

        let outcome = try ModelCatalogImporter.parse(data: json(entries))

        XCTAssertEqual(outcome.models.map(\.model.priority), [1, 2, 3])
        XCTAssertEqual(outcome.models.map(\.model.slug), ["a", "b", "c"])
    }

    // MARK: - File-level rejection

    func testBrokenJSONIsRejected() throws {
        XCTAssertThrowsError(try ModelCatalogImporter.parse(data: Data("{ nope".utf8))) { error in
            XCTAssertEqual(error as? ModelCatalogImporter.ImportError, .notValidJSON)
        }
    }

    func testBareArrayIsRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: [fullEntry()])

        XCTAssertThrowsError(try ModelCatalogImporter.parse(data: data)) { error in
            XCTAssertEqual(error as? ModelCatalogImporter.ImportError, .unexpectedShape)
        }
    }

    func testMissingModelsKeyIsRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: ["providers": []])

        XCTAssertThrowsError(try ModelCatalogImporter.parse(data: data)) { error in
            XCTAssertEqual(error as? ModelCatalogImporter.ImportError, .unexpectedShape)
        }
    }

    func testEmptyModelsArrayIsRejected() throws {
        XCTAssertThrowsError(try ModelCatalogImporter.parse(data: json([]))) { error in
            XCTAssertEqual(error as? ModelCatalogImporter.ImportError, .noModels)
        }
    }

    // MARK: - The whole point: what comes out must be savable

    /// The core guarantee. An imported model that fails ProviderDraft validation greys out
    /// Save and makes the entire form unwritable, which is far worse than not importing.
    func testEveryImportedModelPassesDraftValidation() throws {
        let entries: [[String: Any]] = [
            fullEntry(),
            fullEntry(slug: "tiny", contextWindow: 512, maxContextWindow: 512),
            {
                var entry = fullEntry(slug: "bare")
                entry.removeValue(forKey: "display_name")
                entry.removeValue(forKey: "description")
                entry.removeValue(forKey: "context_window")
                entry.removeValue(forKey: "max_context_window")
                entry.removeValue(forKey: "supported_reasoning_levels")
                entry.removeValue(forKey: "default_reasoning_level")
                entry.removeValue(forKey: "visibility")
                return entry
            }(),
            fullEntry(slug: "weird", efforts: ["minimal"], defaultEffort: "minimal"),
            fullEntry(slug: "narrow", contextWindow: 200_000, maxContextWindow: 1_000)
        ]

        let outcome = try ModelCatalogImporter.parse(data: json(entries))
        XCTAssertEqual(outcome.models.count, entries.count, "none of these should be skipped")

        var provider = ProviderConfiguration(
            id: "imported",
            name: "Imported",
            baseURL: "https://api.example.com/v1"
        )
        provider.models = outcome.models.map(\.model)
        let draft = ProviderDraft(provider: provider)

        XCTAssertTrue(
            draft.errors.isEmpty,
            "imported models must not make the form unsavable: "
                + draft.errors.map { $0.message }.joined(separator: "; ")
        )
    }

    // MARK: - Merging into an existing provider

    private func model(slug: String, contextWindow: Int = 128_000) -> ModelConfiguration {
        ModelConfiguration(
            slug: slug,
            displayName: slug,
            contextWindow: contextWindow,
            maxContextWindow: contextWindow
        )
    }

    func testMergeAppendsModelsThatAreNotThereYet() {
        let result = ModelCatalogImporter.merge(
            imported: [model(slug: "b"), model(slug: "c")],
            into: [model(slug: "a")]
        )

        XCTAssertEqual(result.models.map(\.slug), ["a", "b", "c"])
        XCTAssertEqual(result.added, ["b", "c"])
        XCTAssertTrue(result.overwritten.isEmpty)
    }

    func testMergeReplacesTheSameSlugInPlaceAndKeepsItsIdentity() {
        var existing = [model(slug: "a"), model(slug: "b")]
        existing[1].id = UUID()
        let keptID = existing[1].id

        let result = ModelCatalogImporter.merge(
            imported: [model(slug: "b", contextWindow: 64_000)],
            into: existing
        )

        XCTAssertEqual(result.models.count, 2, "an overwrite must not grow the list")
        XCTAssertEqual(result.models.map(\.slug), ["a", "b"], "and must not reorder it")
        XCTAssertEqual(result.overwritten, ["b"])
        XCTAssertEqual(result.models[1].id, keptID, "the entry keeps its identity")
        XCTAssertEqual(result.models[1].contextWindow, 64_000, "but takes the file's values")
    }

    func testMergeRenumbersPrioritiesOverTheResult() {
        var existing = [model(slug: "a"), model(slug: "b")]
        existing[0].priority = 1_000
        existing[1].priority = 1_007

        let result = ModelCatalogImporter.merge(
            imported: [model(slug: "c")],
            into: existing
        )

        XCTAssertEqual(result.models.map(\.priority), [1, 2, 3])
    }

    func testMergeOntoAnEmptyListIsJustTheImportedModels() {
        let result = ModelCatalogImporter.merge(
            imported: [model(slug: "a"), model(slug: "b")],
            into: []
        )

        XCTAssertEqual(result.models.map(\.slug), ["a", "b"])
        XCTAssertEqual(result.added, ["a", "b"])
    }

    /// Regression guard for the project's strongest red line: the importer must never bring an
    /// unofficial field into storage, no matter what the file carries.
    func testImporterNeverMentionsUnofficialFields() throws {
        let source = try String(
            contentsOf: TestSupport.packageRoot
                .appendingPathComponent("Sources/CodexBridgerCore/ModelCatalogImporter.swift"),
            encoding: .utf8
        )
        for forbidden in ["input_modalities", "supports_search_tool", "video", "pdf", "structured_output", "system_message"] {
            XCTAssertFalse(
                source.contains(forbidden),
                "the importer must not touch \(forbidden)"
            )
        }
    }
}
