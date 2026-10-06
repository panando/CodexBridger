import XCTest
@testable import CodexBridgerCore

/// Seam: ModelCatalogGenerator public API.
///
/// Expected values are taken from the parameters the user configured, not from
/// the generator, so these assertions can actually disagree with the code.
final class ModelCatalogGeneratorTests: XCTestCase {

    private func generator() -> ModelCatalogGenerator {
        ModelCatalogGenerator(templateSource: StaticCatalogTemplate())
    }

    func testCatalogHasOneEntryPerModelInConfiguredOrder() throws {
        let provider = TestSupport.sampleProvider()
        let catalog = try generator().makeCatalog(provider: provider, preferredTemplateSlug: "gpt-5.5")
        let models = try XCTUnwrap(catalog["models"] as? [[String: Any]])
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models[0]["slug"] as? String, "demo-large")
        XCTAssertEqual(models[1]["slug"] as? String, "demo-small")
    }

    func testUserParametersAreWrittenIntoTheEntry() throws {
        let provider = TestSupport.sampleProvider()
        let catalog = try generator().makeCatalog(provider: provider, preferredTemplateSlug: "gpt-5.5")
        let models = try XCTUnwrap(catalog["models"] as? [[String: Any]])
        let large = models[0]
        XCTAssertEqual(large["display_name"] as? String, "Demo Large")
        XCTAssertEqual(large["description"] as? String, "Large demo model")
        XCTAssertEqual(large["context_window"] as? Int, 200_000)
        XCTAssertEqual(large["max_context_window"] as? Int, 200_000)
        XCTAssertEqual(large["default_reasoning_level"] as? String, "high")
        XCTAssertEqual(large["visibility"] as? String, "list")
        let levels = try XCTUnwrap(large["supported_reasoning_levels"] as? [[String: String]])
        XCTAssertEqual(levels.map { $0["effort"] }, ["low", "medium", "high"])
    }

    func testTemplateSlugNeverLeaksIntoGeneratedCatalog() throws {
        let provider = TestSupport.sampleProvider()
        let catalog = try generator().makeCatalog(provider: provider, preferredTemplateSlug: "gpt-5.5")
        let json = try ModelCatalogGenerator.serialize(catalog)
        XCTAssertFalse(json.contains("gpt-5.5"))
    }

    func testEntriesAreOrderedByPriority() throws {
        let provider = TestSupport.sampleProvider()
        let catalog = try generator().makeCatalog(provider: provider, preferredTemplateSlug: "t")
        let models = try XCTUnwrap(catalog["models"] as? [[String: Any]])
        XCTAssertEqual(models[0]["priority"] as? Int, 1000)
        XCTAssertEqual(models[1]["priority"] as? Int, 1001)
    }

    func testDefaultEffortOutsideSupportedListFallsBackToFirstSupported() throws {
        let model = ModelConfiguration(
            slug: "m",
            displayName: "M",
            supportedReasoningEfforts: [.low, .medium],
            defaultReasoningEffort: .ultra
        )
        let provider = TestSupport.sampleProvider(models: [model])
        let catalog = try generator().makeCatalog(provider: provider, preferredTemplateSlug: "t")
        let entry = try XCTUnwrap((catalog["models"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["default_reasoning_level"] as? String, "low")
    }

    func testMaxContextWindowIsNeverBelowContextWindow() throws {
        let model = ModelConfiguration(
            slug: "m",
            displayName: "M",
            contextWindow: 300_000,
            maxContextWindow: 1_000
        )
        let provider = TestSupport.sampleProvider(models: [model])
        let catalog = try generator().makeCatalog(provider: provider, preferredTemplateSlug: "t")
        let entry = try XCTUnwrap((catalog["models"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["context_window"] as? Int, 300_000)
        XCTAssertEqual(entry["max_context_window"] as? Int, 300_000)
    }

    func testModelWithNoSupportedEffortsStillGetsOne() throws {
        let model = ModelConfiguration(
            slug: "m",
            displayName: "M",
            supportedReasoningEfforts: [],
            defaultReasoningEffort: .medium
        )
        let provider = TestSupport.sampleProvider(models: [model])
        let catalog = try generator().makeCatalog(provider: provider, preferredTemplateSlug: "t")
        let entry = try XCTUnwrap((catalog["models"] as? [[String: Any]])?.first)
        let levels = try XCTUnwrap(entry["supported_reasoning_levels"] as? [[String: String]])
        XCTAssertEqual(levels.map { $0["effort"] }, ["medium"])
    }

    func testEveryEntryCarriesAgentInstructions() throws {
        let provider = TestSupport.sampleProvider()
        let catalog = try generator().makeCatalog(provider: provider, preferredTemplateSlug: "t")
        let models = try XCTUnwrap(catalog["models"] as? [[String: Any]])
        for entry in models {
            let hasBase = (entry["base_instructions"] as? String)?.isEmpty == false
            let messages = entry["model_messages"] as? [String: Any]
            let hasTemplate = (messages?["instructions_template"] as? String)?.isEmpty == false
            XCTAssertTrue(hasBase || hasTemplate,
                          "Codex rejects a catalog entry without agent instructions")
        }
    }

    func testRejectsEmptyProvider() {
        let provider = TestSupport.sampleProvider(models: [])
        XCTAssertThrowsError(try generator().makeCatalog(provider: provider, preferredTemplateSlug: "t")) { error in
            XCTAssertEqual(error as? ModelCatalogGenerator.GenerationError, .noModels(providerID: "demo"))
        }
    }

    func testRejectsDuplicateSlugs() {
        let provider = TestSupport.sampleProvider(models: [
            ModelConfiguration(slug: "dup", displayName: "A"),
            ModelConfiguration(slug: "dup", displayName: "B")
        ])
        XCTAssertThrowsError(try generator().makeCatalog(provider: provider, preferredTemplateSlug: "t")) { error in
            XCTAssertEqual(error as? ModelCatalogGenerator.GenerationError, .duplicateSlug(slug: "dup"))
        }
    }

    func testRejectsEmptySlugAndNonPositiveContextWindow() {
        let blank = TestSupport.sampleProvider(models: [ModelConfiguration(slug: "  ", displayName: "A")])
        XCTAssertThrowsError(try generator().makeCatalog(provider: blank, preferredTemplateSlug: "t"))
        let zero = TestSupport.sampleProvider(models: [
            ModelConfiguration(slug: "z", displayName: "Z", contextWindow: 0)
        ])
        XCTAssertThrowsError(try generator().makeCatalog(provider: zero, preferredTemplateSlug: "t"))
    }

    func testSerializedCatalogIsStableAcrossRuns() throws {
        let provider = TestSupport.sampleProvider()
        let first = try ModelCatalogGenerator.serialize(
            generator().makeCatalog(provider: provider, preferredTemplateSlug: "t")
        )
        let second = try ModelCatalogGenerator.serialize(
            generator().makeCatalog(provider: provider, preferredTemplateSlug: "t")
        )
        XCTAssertEqual(first, second, "activation must be reproducible byte for byte")
    }
}
