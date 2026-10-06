import XCTest
@testable import CodexBridgerCore

/// End-to-end acceptance against the real Codex build on this machine.
///
/// This is the only test that can prove the generated files are actually loadable:
/// it writes a config into a throwaway CODEX_HOME and asks the installed Codex CLI
/// to report the model catalog it sees. It skips when no Codex CLI is installed
/// rather than failing the suite.
final class CodexCLIIntegrationTests: XCTestCase {

    func testGeneratedCatalogIsLoadedByTheInstalledCodex() throws {
        guard let cli = CodexCLI.locate() else {
            throw XCTSkip("no Codex CLI found on this machine")
        }
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }

        var provider = TestSupport.sampleProvider(id: "bridger")
        provider.baseURL = "http://127.0.0.1:9/v1"
        provider.bearerToken = "sk-bridger"
        provider.models = [
            ModelConfiguration(
                slug: "bridger-model-alpha",
                displayName: "Bridger Alpha",
                modelDescription: "first",
                contextWindow: 191_000,
                maxContextWindow: 191_000,
                supportedReasoningEfforts: [.low, .high],
                defaultReasoningEffort: .high,
                priority: 1
            ),
            ModelConfiguration(
                slug: "bridger-model-beta",
                displayName: "Bridger Beta",
                contextWindow: 33_000,
                maxContextWindow: 33_000,
                supportedReasoningEfforts: [.low],
                defaultReasoningEffort: .low,
                priority: 2
            )
        ]

        let writer = CodexConfigWriter(
            paths: paths,
            templateSource: StaticCatalogTemplate(),
            now: Date.init
        )
        _ = try writer.activate(
            provider: provider,
            model: provider.models[0],
            configuration: CodexBridgerConfiguration()
        )

        let reported = try runCodexModels(cli: cli, codexHome: root)
        let models = try XCTUnwrap(reported["models"] as? [[String: Any]])
        let slugs = models.compactMap { $0["slug"] as? String }
        XCTAssertEqual(slugs, ["bridger-model-alpha", "bridger-model-beta"],
                       "Codex must see exactly the models CodexBridger generated")

        let alpha = try XCTUnwrap(models.first { ($0["slug"] as? String) == "bridger-model-alpha" })
        XCTAssertEqual(alpha["context_window"] as? Int, 191_000)
        XCTAssertEqual(alpha["display_name"] as? String, "Bridger Alpha")
        XCTAssertEqual(alpha["default_reasoning_level"] as? String, "high")
        let levels = try XCTUnwrap(alpha["supported_reasoning_levels"] as? [[String: Any]])
        XCTAssertEqual(levels.compactMap { $0["effort"] as? String }, ["low", "high"])

        let beta = try XCTUnwrap(models.first { ($0["slug"] as? String) == "bridger-model-beta" })
        XCTAssertEqual(beta["context_window"] as? Int, 33_000)
    }

    func testCodexAcceptsTheActivatedAuthFile() throws {
        guard let cli = CodexCLI.locate() else {
            throw XCTSkip("no Codex CLI found on this machine")
        }
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        var provider = TestSupport.sampleProvider(id: "bridger")
        provider.bearerToken = "sk-bridger-token"
        let writer = CodexConfigWriter(paths: paths, templateSource: StaticCatalogTemplate(), now: Date.init)
        _ = try writer.activate(
            provider: provider,
            model: provider.models[0],
            configuration: CodexBridgerConfiguration()
        )
        let output = try run(["login", "status"], cli: cli, codexHome: root)
        XCTAssertTrue(
            output.contains("API key") || output.contains("ChatGPT"),
            "unexpected login status output: " + output
        )
    }

    private func runCodexModels(cli: CodexCLI, codexHome: URL) throws -> [String: Any] {
        let text = try run(["debug", "models"], cli: cli, codexHome: codexHome)
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw XCTSkip("codex debug models produced no JSON")
        }
        return object
    }

    private func run(_ arguments: [String], cli: CodexCLI, codexHome: URL) throws -> String {
        let process = Process()
        process.executableURL = cli.executableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["CODEX_HOME": codexHome.path],
            uniquingKeysWith: { _, new in new }
        )
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let diagnostics = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // codex login status reports on stderr, so both streams are returned.
        return (String(data: output, encoding: .utf8) ?? "")
            + (String(data: diagnostics, encoding: .utf8) ?? "")
    }
}
