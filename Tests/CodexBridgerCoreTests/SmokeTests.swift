import XCTest
@testable import CodexBridgerCore

final class SmokeTests: XCTestCase {
    func testPathsHonorCodexHome() {
        let paths = CodexPaths(environment: ["CODEX_HOME": "/tmp/codexbridger-smoke"])
        XCTAssertEqual(paths.codexHome.path, "/tmp/codexbridger-smoke")
        XCTAssertEqual(paths.configTOML.path, "/tmp/codexbridger-smoke/config.toml")
    }
}
