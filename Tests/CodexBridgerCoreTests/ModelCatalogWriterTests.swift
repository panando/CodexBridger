import XCTest
@testable import CodexBridgerCore

/// Seam: ModelCatalogWriter — the single place <provider>-model-catalog.json is produced.
///
/// Activation and "save a provider Codex is currently pointed at" both go through this
/// writer, so the two paths cannot drift apart. These tests pin the rendered bytes, the
/// skip-when-identical rule, and the failures that must leave no half-written file behind.
final class ModelCatalogWriterTests: XCTestCase {

    /// Supplies no template at all.
    private struct EmptyTemplateSource: CatalogTemplateSource {
        var sourceDescription: String { "empty" }
        func templateEntry(preferredSlug: String) throws -> [String: Any]? { nil }
    }

    /// A template that is missing the instructions Codex requires.
    private struct NoInstructionsTemplateSource: CatalogTemplateSource {
        var sourceDescription: String { "no instructions" }
        func templateEntry(preferredSlug: String) throws -> [String: Any]? {
            ["slug": preferredSlug, "display_name": preferredSlug]
        }
    }

    private func makeWriter(
        _ paths: CodexPaths,
        template: CatalogTemplateSource = StaticCatalogTemplate()
    ) -> ModelCatalogWriter {
        ModelCatalogWriter(paths: paths, templateSource: template)
    }

    private func model(
        slug: String,
        contextWindow: Int = 128_000,
        maxContextWindow: Int? = nil
    ) -> ModelConfiguration {
        ModelConfiguration(
            slug: slug,
            displayName: slug,
            contextWindow: contextWindow,
            maxContextWindow: maxContextWindow ?? contextWindow
        )
    }

    // MARK: - Rendering

    func testRenderProducesTheCatalogForTheProviderAndWritesNothing() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)

        let rendered = try writer.render(
            provider: TestSupport.sampleProvider(),
            preferredTemplateSlug: "gpt-5.5"
        )

        XCTAssertEqual(rendered.providerID, "demo")
        XCTAssertEqual(rendered.url, paths.catalog(for: "demo"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: rendered.url.path),
            "render must not touch the disk"
        )

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(rendered.json.utf8)) as? [String: Any]
        )
        let models = try XCTUnwrap(object["models"] as? [[String: Any]])
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models[0]["slug"] as? String, "demo-large")
        XCTAssertEqual(models[1]["slug"] as? String, "demo-small")
    }

    func testRenderIsDeterministic() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)
        let provider = TestSupport.sampleProvider()

        let first = try writer.render(provider: provider, preferredTemplateSlug: "gpt-5.5")
        let second = try writer.render(provider: provider, preferredTemplateSlug: "gpt-5.5")

        XCTAssertEqual(first.json, second.json)
    }

    /// The move-only guarantee for P1: activation writes exactly what the writer renders.
    func testActivationWritesExactlyWhatRenderProduces() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let provider = TestSupport.sampleProvider()
        let configuration = CodexBridgerConfiguration(
            providers: [provider],
            activeProviderID: provider.id,
            activeModelSlug: provider.models[0].slug
        )

        let rendered = try makeWriter(paths).render(
            provider: provider,
            preferredTemplateSlug: configuration.catalogTemplateSlug
        )
        let result = try CodexConfigWriter(
            paths: paths,
            templateSource: StaticCatalogTemplate(),
            now: { Date(timeIntervalSince1970: 1_791_000_000) }
        ).activate(
            provider: provider,
            model: provider.models[0],
            configuration: configuration
        )

        XCTAssertEqual(result.catalogJSON, rendered.json)
        XCTAssertEqual(result.catalogURL, rendered.url)
        XCTAssertEqual(
            try String(contentsOf: paths.catalog(for: "demo"), encoding: .utf8),
            rendered.json,
            "the file on disk must be exactly the rendered catalog"
        )
    }

    // MARK: - Writing

    func testWriteCreatesTheFileAndItsDirectory() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)
        let rendered = try writer.render(
            provider: TestSupport.sampleProvider(),
            preferredTemplateSlug: "gpt-5.5"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.modelCatalogsDirectory.path))
        try writer.write(rendered)

        XCTAssertTrue(FileManager.default.fileExists(atPath: rendered.url.path))
        XCTAssertEqual(
            try String(contentsOf: rendered.url, encoding: .utf8),
            rendered.json
        )
    }

    func testWriteIfChangedWritesWhenTheFileIsMissing() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)

        let outcome = try writer.writeIfChanged(
            provider: TestSupport.sampleProvider(),
            preferredTemplateSlug: "gpt-5.5"
        )

        XCTAssertEqual(outcome.action, .written)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.catalog.url.path))
    }

    /// The rule that keeps saving a provider from churning the file: same bytes, no write.
    func testWriteIfChangedSkipsWhenTheBytesAlreadyMatch() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)
        let provider = TestSupport.sampleProvider()

        _ = try writer.writeIfChanged(provider: provider, preferredTemplateSlug: "gpt-5.5")

        // Backdate the file so a rewrite cannot hide behind the clock.
        let old = Date(timeIntervalSince1970: 1_000_000)
        let url = paths.catalog(for: provider.id)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)

        let outcome = try writer.writeIfChanged(provider: provider, preferredTemplateSlug: "gpt-5.5")

        XCTAssertEqual(outcome.action, .unchanged)
        let after = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        )
        XCTAssertEqual(after, old, "an identical catalog must not be rewritten")
    }

    func testWriteIfChangedRewritesWhenAModelParameterChanges() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)
        var provider = TestSupport.sampleProvider()

        let before = try writer.writeIfChanged(provider: provider, preferredTemplateSlug: "gpt-5.5")
        provider.models[0].contextWindow = 300_000
        provider.models[0].maxContextWindow = 300_000
        let after = try writer.writeIfChanged(provider: provider, preferredTemplateSlug: "gpt-5.5")

        XCTAssertEqual(after.action, .written)
        XCTAssertNotEqual(before.catalog.json, after.catalog.json)
        XCTAssertEqual(
            try String(contentsOf: paths.catalog(for: provider.id), encoding: .utf8),
            after.catalog.json
        )
    }

    // MARK: - Failures must not leave a file behind

    func testRenderThrowsWhenNoTemplateIsAvailable() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths, template: EmptyTemplateSource())

        XCTAssertThrowsError(
            try writer.render(provider: TestSupport.sampleProvider(), preferredTemplateSlug: "gpt-5.5")
        ) { error in
            XCTAssertEqual(error as? ModelCatalogGenerator.GenerationError, .noUsableTemplate)
        }
    }

    func testRenderThrowsWhenTheTemplateHasNoInstructions() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths, template: NoInstructionsTemplateSource())

        XCTAssertThrowsError(
            try writer.render(provider: TestSupport.sampleProvider(), preferredTemplateSlug: "gpt-5.5")
        ) { error in
            XCTAssertEqual(error as? ModelCatalogGenerator.GenerationError, .templateMissingInstructions)
        }
    }

    func testWriteIfChangedLeavesNoFileBehindWhenRenderingFails() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths, template: EmptyTemplateSource())

        XCTAssertThrowsError(
            try writer.writeIfChanged(provider: TestSupport.sampleProvider(), preferredTemplateSlug: "gpt-5.5")
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.catalog(for: "demo").path),
            "a failed render must not leave a catalog behind"
        )
    }

    func testRenderThrowsWhenTheProviderHasNoModels() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)
        var provider = TestSupport.sampleProvider()
        provider.models = []

        XCTAssertThrowsError(
            try writer.render(provider: provider, preferredTemplateSlug: "gpt-5.5")
        ) { error in
            XCTAssertEqual(
                error as? ModelCatalogGenerator.GenerationError,
                .noModels(providerID: "demo")
            )
        }
    }

    func testRenderThrowsOnDuplicateSlugs() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)
        let provider = TestSupport.sampleProvider(
            models: [model(slug: "same"), model(slug: "same")]
        )

        XCTAssertThrowsError(
            try writer.render(provider: provider, preferredTemplateSlug: "gpt-5.5")
        ) { error in
            XCTAssertEqual(
                error as? ModelCatalogGenerator.GenerationError,
                .duplicateSlug(slug: "same")
            )
        }
    }

    func testRenderThrowsOnAnEmptySlug() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)
        let provider = TestSupport.sampleProvider(models: [model(slug: "   ")])

        XCTAssertThrowsError(
            try writer.render(provider: provider, preferredTemplateSlug: "gpt-5.5")
        ) { error in
            XCTAssertEqual(
                error as? ModelCatalogGenerator.GenerationError,
                .emptySlug(providerID: "demo")
            )
        }
    }

    func testRenderThrowsOnANonPositiveContextWindow() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)
        let provider = TestSupport.sampleProvider(models: [model(slug: "zero", contextWindow: 0)])

        XCTAssertThrowsError(
            try writer.render(provider: provider, preferredTemplateSlug: "gpt-5.5")
        ) { error in
            XCTAssertEqual(
                error as? ModelCatalogGenerator.GenerationError,
                .invalidContextWindow(slug: "zero")
            )
        }
    }

    // MARK: - Paths

    func testTheCatalogPathIsScopedToTheProviderID() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)

        let rendered = try writer.render(
            provider: TestSupport.sampleProvider(id: "cpa"),
            preferredTemplateSlug: "gpt-5.5"
        )

        XCTAssertEqual(rendered.url.lastPathComponent, "cpa-model-catalog.json")
        XCTAssertEqual(rendered.url.deletingLastPathComponent(), paths.modelCatalogsDirectory)
    }
}
