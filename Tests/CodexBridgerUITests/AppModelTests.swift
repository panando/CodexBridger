import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: AppModel.load
///
/// Covers what the window shows for each on-disk state, because a silently empty provider
/// list is indistinguishable from deleted data for the person using the app.
@MainActor
final class AppModelTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("appmodel-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    private func write(_ contents: String) throws {
        let directory = paths.appConfiguration.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: paths.appConfiguration)
    }

    func testFreshInstallLoadsEmptyWithoutAnError() {
        let model = AppModel(paths: paths)
        model.load()
        XCTAssertTrue(model.configuration.providers.isEmpty)
        XCTAssertNil(model.loadErrorMessage)
    }

    func testValidConfigurationLoadsWithoutAnError() throws {
        try write("""
        { "activeProviderID": "demo", "providers": [ { "id": "demo", "name": "示例",
          "baseURL": "https://api.example.com/v1" } ] }
        """)
        let model = AppModel(paths: paths)
        model.load()
        XCTAssertNil(model.loadErrorMessage)
        XCTAssertEqual(model.configuration.providers.count, 1)
        XCTAssertEqual(model.selectedProviderID, "demo")
    }

    func testUnreadableConfigurationSurfacesAnErrorInsteadOfLookingEmpty() throws {
        try write("{ not json at all")
        let model = AppModel(paths: paths)
        model.load()
        let message = try XCTUnwrap(
            model.loadErrorMessage,
            "a decode failure must be reported, not silently shown as zero providers"
        )
        XCTAssertTrue(message.contains("配置"))
        XCTAssertTrue(model.configuration.providers.isEmpty)
    }

    func testStructurallyCorruptProvidersAlsoSurfacesAnError() throws {
        try write("{\"providers\": \"not-an-array\"}")
        let model = AppModel(paths: paths)
        model.load()
        XCTAssertNotNil(
            model.loadErrorMessage,
            "a corrupt providers value must not be silently replaced with an empty list"
        )
    }

    func testPartialConfigurationIsNotAnError() throws {
        try write("{\"providers\": [ { \"id\": \"demo\", \"name\": \"示例\" } ]}")
        let model = AppModel(paths: paths)
        model.load()
        XCTAssertNil(model.loadErrorMessage, "missing keys should be filled with defaults")
        XCTAssertEqual(model.configuration.providers.first?.id, "demo")
    }
}
