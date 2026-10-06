import XCTest
@testable import CodexBridgerCore

/// Seam: CodexPaths public API.
final class CodexPathsTests: XCTestCase {

    func testHonorsCodexHomeOverride() {
        let paths = CodexPaths(environment: ["CODEX_HOME": "/tmp/custom-codex"])
        XCTAssertEqual(paths.codexHome.path, "/tmp/custom-codex")
        XCTAssertEqual(paths.configTOML.path, "/tmp/custom-codex/config.toml")
        XCTAssertEqual(paths.authJSON.path, "/tmp/custom-codex/auth.json")
        XCTAssertEqual(paths.modelCatalogsDirectory.path, "/tmp/custom-codex/model-catalogs")
        XCTAssertEqual(paths.backupDirectory.path, "/tmp/custom-codex/backup/config-backup")
        XCTAssertEqual(paths.appConfiguration.path, "/tmp/custom-codex/codexbridger/config.json")
    }

    func testExpandsTildeInCodexHome() {
        let paths = CodexPaths(environment: ["CODEX_HOME": "~/.codex-alt"])
        XCTAssertFalse(paths.codexHome.path.hasPrefix("~"))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(paths.codexHome.path, home + "/.codex-alt")
    }

    func testDefaultsToDotCodexInHomeDirectory() {
        let paths = CodexPaths(environment: [:])
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(paths.codexHome.path, home + "/.codex")
    }

    func testBlankOverrideFallsBackToDefault() {
        let paths = CodexPaths(environment: ["CODEX_HOME": "   "])
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(paths.codexHome.path, home + "/.codex")
    }

    func testCatalogFileNameUsesProviderID() {
        let paths = CodexPaths(environment: ["CODEX_HOME": "/tmp/x"])
        XCTAssertEqual(paths.catalog(for: "cpa").lastPathComponent, "cpa-model-catalog.json")
        XCTAssertEqual(paths.catalog(for: "cpa").deletingLastPathComponent().lastPathComponent, "model-catalogs")
    }

    func testProviderIdentifierValidation() {
        XCTAssertTrue(ProviderConfiguration.isValidIdentifier("cpa"))
        XCTAssertTrue(ProviderConfiguration.isValidIdentifier("my-provider_1"))
        XCTAssertFalse(ProviderConfiguration.isValidIdentifier(""))
        XCTAssertFalse(ProviderConfiguration.isValidIdentifier("has.dot"),
                       "a dot would create a nested TOML table")
        XCTAssertFalse(ProviderConfiguration.isValidIdentifier("has space"))
        XCTAssertFalse(ProviderConfiguration.isValidIdentifier("has/slash"))
    }
}
