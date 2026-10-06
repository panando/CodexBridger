import XCTest
@testable import CodexBridgerCore

/// Seam: ConfigurationStore public API.
///
/// Covers the requirement that providers, models and the active selection survive
/// a restart.
final class PersistenceTests: XCTestCase {

    func testEmptyHomeLoadsDefaults() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let store = ConfigurationStore(paths: paths)
        let configuration = try store.load()
        XCTAssertTrue(configuration.providers.isEmpty)
        XCTAssertNil(configuration.activeProviderID)
        XCTAssertFalse(store.configurationExists)
    }

    func testProvidersModelsAndActiveSelectionSurviveReload() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let store = ConfigurationStore(paths: paths)

        var configuration = CodexBridgerConfiguration()
        configuration.providers = [TestSupport.sampleProvider(id: "alpha"), TestSupport.sampleProvider(id: "beta")]
        configuration.activeProviderID = "beta"
        configuration.activeModelSlug = "demo-small"
        configuration.modelReasoningEffort = .xhigh
        configuration.modelVerbosity = .high
        try store.save(configuration)

        // A brand new store instance stands in for an app restart.
        let reloaded = try ConfigurationStore(paths: paths).load()
        XCTAssertEqual(reloaded.providers.count, 2)
        XCTAssertEqual(reloaded.activeProviderID, "beta")
        XCTAssertEqual(reloaded.activeModelSlug, "demo-small")
        XCTAssertEqual(reloaded.modelReasoningEffort, .xhigh)
        XCTAssertEqual(reloaded.modelVerbosity, .high)
        XCTAssertEqual(reloaded.providers[0].models.count, 2)
        XCTAssertEqual(reloaded.providers[0].models[0].slug, "demo-large")
        XCTAssertEqual(reloaded.providers[0].models[0].supportedReasoningEfforts, [.low, .medium, .high])
        XCTAssertEqual(reloaded.providers[0].models[0].contextWindow, 200_000)
    }

    func testStoredUnderItsOwnSubfolderOfCodexHome() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        try ConfigurationStore(paths: paths).save(CodexBridgerConfiguration())
        XCTAssertEqual(paths.appConfiguration.lastPathComponent, "config.json")
        XCTAssertEqual(paths.appConfiguration.deletingLastPathComponent().lastPathComponent, "codexbridger")
        XCTAssertEqual(
            paths.appConfiguration.deletingLastPathComponent().deletingLastPathComponent().path,
            root.path
        )
    }

    func testCorruptFileThrowsInsteadOfSilentlyResetting() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        try AtomicFile.write("{ not json", to: paths.appConfiguration)
        XCTAssertThrowsError(try ConfigurationStore(paths: paths).load())
    }

    func testRemovingProviderPersists() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let store = ConfigurationStore(paths: paths)
        var configuration = CodexBridgerConfiguration()
        configuration.providers = [TestSupport.sampleProvider(id: "alpha"), TestSupport.sampleProvider(id: "beta")]
        try store.save(configuration)
        configuration.providers.removeAll { $0.id == "alpha" }
        try store.save(configuration)
        XCTAssertEqual(try store.load().providers.map { $0.id }, ["beta"])
    }
}
