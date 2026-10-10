import XCTest
@testable import CodexBridgerCore

/// Seam: the persisted configuration decoder.
///
/// The app writes every key, but a hand-edited or partially written file (or one from an
/// older build) must still load. Synthesized Codable requires every key even when the
/// property has a default, so a single missing key used to fail the whole file and the UI
/// showed an empty provider list as if the data were gone.
final class ConfigurationDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> CodexBridgerConfiguration {
        try JSONDecoder().decode(CodexBridgerConfiguration.self, from: Data(json.utf8))
    }

    func testMinimalProviderDecodesWithDocumentedDefaults() throws {
        let json = """
        { "providers": [ { "id": "demo", "name": "示例", "baseURL": "https://api.example.com/v1" } ] }
        """
        let configuration = try decode(json)
        XCTAssertEqual(configuration.providers.count, 1)
        let provider = try XCTUnwrap(configuration.providers.first)
        XCTAssertEqual(provider.id, "demo")
        XCTAssertEqual(provider.credentialMode, .none)
        XCTAssertFalse(provider.requiresOpenAIAuth)
        XCTAssertEqual(provider.bearerToken, "")
        XCTAssertEqual(provider.queryParams, [:])
        XCTAssertEqual(provider.httpHeaders, [:])
        XCTAssertEqual(provider.environmentHTTPHeaders, [:])
        XCTAssertNil(provider.requestMaxRetries)
        XCTAssertNil(provider.supportsWebsockets)
        XCTAssertEqual(provider.commandAuth.command, "")
        XCTAssertEqual(provider.commandAuth.args, [])
        XCTAssertTrue(provider.models.isEmpty)
    }

    func testMinimalModelDecodesWithDefaults() throws {
        let json = """
        { "providers": [ { "id": "demo", "name": "示例", "baseURL": "https://x.example.com",
          "models": [ { "slug": "demo-large" } ] } ] }
        """
        let configuration = try decode(json)
        let model = try XCTUnwrap(configuration.providers.first?.models.first)
        XCTAssertEqual(model.slug, "demo-large")
        XCTAssertEqual(model.displayName, "demo-large")
        XCTAssertEqual(model.contextWindow, 128_000)
        XCTAssertEqual(model.maxContextWindow, 128_000)
        XCTAssertEqual(model.defaultReasoningEffort, .medium)
        XCTAssertEqual(model.visibility, .list)
        XCTAssertEqual(model.priority, 1)
    }

    func testMissingTopLevelKeysDecodeToSensibleDefaults() throws {
        let configuration = try decode("{}")
        XCTAssertTrue(configuration.providers.isEmpty)
        XCTAssertNil(configuration.activeProviderID)
        XCTAssertNil(configuration.modelReasoningEffort)
        XCTAssertEqual(configuration.catalogTemplateSlug, "gpt-5.5")
        XCTAssertEqual(configuration.schemaVersion, CodexBridgerConfiguration.currentSchemaVersion)
    }

    func testUnknownKeysAreIgnored() throws {
        let json = """
        { "somethingNew": 42, "providers": [ { "id": "demo", "name": "示例",
          "baseURL": "https://x.example.com", "notARealKey": true } ] }
        """
        let configuration = try decode(json)
        XCTAssertEqual(configuration.providers.first?.id, "demo")
    }

    func testWrongTypeFallsBackInsteadOfFailingTheWholeFile() throws {
        let json = """
        { "providers": [ { "id": "demo", "name": "示例", "baseURL": "https://x.example.com",
          "requestMaxRetries": "not-a-number" } ] }
        """
        let configuration = try decode(json)
        XCTAssertEqual(configuration.providers.first?.id, "demo")
        XCTAssertNil(configuration.providers.first?.requestMaxRetries)
    }

    func testShippedExampleStillRoundTripsExactly() throws {
        let original = CodexBridgerConfiguration(
            providers: [
                ProviderConfiguration(
                    id: "demo",
                    name: "示例提供商",
                    baseURL: "https://api.example.com/v1",
                    credentialMode: .bearerToken,
                    requiresOpenAIAuth: true,
                    bearerToken: "sk-example-token",
                    queryParams: ["api-version": "2025-04-01"],
                    httpHeaders: ["X-Example-Header": "example-value"],
                    environmentHTTPHeaders: ["X-Features": "MY_FEATURES"],
                    requestMaxRetries: 3,
                    supportsWebsockets: false,
                    models: [
                        ModelConfiguration(
                            slug: "demo-large",
                            displayName: "Demo Large",
                            modelDescription: "示例大模型",
                            contextWindow: 200_000,
                            maxContextWindow: 200_000,
                            supportedReasoningEfforts: [.low, .medium, .high, .xhigh],
                            defaultReasoningEffort: .high,
                            priority: 1
                        )
                    ]
                )
            ],
            activeProviderID: "demo",
            activeModelSlug: "demo-large",
            modelReasoningEffort: .xhigh,
            modelReasoningSummary: .concise,
            modelVerbosity: .medium,
            modelSupportsReasoningSummaries: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodexBridgerConfiguration.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testGenuinelyCorruptJSONStillThrows() {
        XCTAssertThrowsError(try decode("{ this is not json"))
        XCTAssertThrowsError(try decode("{\"providers\": \"not-an-array\"}"))
    }
    /// The strict-override table is part of the app's own configuration and
    /// must survive a round trip; a config written before it existed decodes
    /// to the observed defaults rather than failing.
    func testStrictOverridesDecodeToTheObservedDefaultsWhenAbsent() throws {
        let json = #"{"providers": []}"#
        let config = try JSONDecoder().decode(
            CodexBridgerConfiguration.self, from: Data(json.utf8)
        )
        XCTAssertFalse(config.autoReviewStrictOverrides.value(for: "glm-5.3-flash"))
        XCTAssertTrue(config.autoReviewStrictOverrides.value(for: "kimi-k2.7-code"))
    }

    func testStrictOverridesSurviveARoundTrip() throws {
        var config = CodexBridgerConfiguration()
        config.autoReviewStrictOverrides.set(false, for: "mimo-v2.6-flash")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CodexBridgerConfiguration.self, from: data)
        XCTAssertFalse(decoded.autoReviewStrictOverrides.value(for: "mimo-v2.6-flash"))
        XCTAssertFalse(decoded.autoReviewStrictOverrides.value(for: "glm-5.3-flash"))
    }

}