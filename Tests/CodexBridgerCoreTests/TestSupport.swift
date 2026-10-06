import Foundation
import XCTest
@testable import CodexBridgerCore

/// Shared helpers for the suite.
///
/// Every test builds its own throwaway Codex home. Nothing in the suite may touch
/// the real ~/.codex, so CodexPaths is always constructed explicitly rather than
/// from the process environment.
enum TestSupport {
    /// Package root, derived from this file location.
    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var baseDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CODE_BRIDGER_TEST_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: "/tmp/codexbridger-tests", isDirectory: true)
    }

    static func makeTemporaryCodexHome() throws -> (paths: CodexPaths, root: URL) {
        let root = baseDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (CodexPaths(codexHome: root), root)
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func sampleProvider(
        id: String = "demo",
        models: [ModelConfiguration]? = nil
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            id: id,
            name: "Demo Provider",
            baseURL: "https://api.example.com/v1",
            credentialMode: .bearerToken,
            requiresOpenAIAuth: true,
            bearerToken: "sk-demo-token",
            models: models ?? [
                ModelConfiguration(
                    slug: "demo-large",
                    displayName: "Demo Large",
                    modelDescription: "Large demo model",
                    contextWindow: 200_000,
                    maxContextWindow: 200_000,
                    supportedReasoningEfforts: [.low, .medium, .high],
                    defaultReasoningEffort: .high,
                    priority: 1
                ),
                ModelConfiguration(
                    slug: "demo-small",
                    displayName: "Demo Small",
                    contextWindow: 64_000,
                    maxContextWindow: 64_000,
                    supportedReasoningEfforts: [.low],
                    defaultReasoningEffort: .low,
                    priority: 2
                )
            ]
        )
    }

    static func json(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "TestSupport", code: 1)
        }
        return object
    }
}
