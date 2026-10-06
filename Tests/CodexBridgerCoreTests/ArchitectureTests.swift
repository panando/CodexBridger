import XCTest
@testable import CodexBridgerCore

/// Architecture guards for requirements that are easy to regress silently.
final class ArchitectureTests: XCTestCase {

    private func swiftSources() throws -> [URL] {
        let sources = TestSupport.packageRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            throw XCTSkip("Sources directory not found")
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    func testNoCDPInjectionCodeRemains() throws {
        let forbidden = [
            "CDP",
            "chrome-remote",
            "remote-debugging-port",
            "webSocketDebuggerUrl",
            "Runtime.evaluate",
            "addScriptToEvaluateOnNewDocument",
            "9222"
        ]
        for file in try swiftSources() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                let message = "CDP artefact [" + token + "] found in " + file.lastPathComponent
                XCTAssertFalse(contents.contains(token), message)
            }
        }
    }

    func testPackageHasNoExternalDependencies() throws {
        let manifest = try String(
            contentsOf: TestSupport.packageRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            manifest.contains(".package(url:"),
            "the package must stay dependency free so it builds offline"
        )
    }

    func testCoreSourcesArePresent() throws {
        let coreFiles = try swiftSources().filter { $0.path.contains("/CodexBridgerCore/") }
        XCTAssertGreaterThan(coreFiles.count, 5)
    }
}
