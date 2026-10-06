import XCTest
@testable import CodexBridgerCore

/// Seam: CodexConfigWriter.activate(provider:model:configuration:).
///
/// This is the acceptance surface for the whole product: after activation, ~/.codex
/// must contain a config.toml, auth.json and <provider>-model-catalog.json that
/// Codex can load, and the previous files must be recoverable from backup.
final class CodexConfigWriterTests: XCTestCase {

    private static let fixedDate: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 5
        components.hour = 19; components.minute = 30
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    /// Keys Codex documents for [model_providers.<id>] plus its .auth sub-table.
    private static let documentedProviderKeys: Set<String> = [
        "name", "base_url", "env_key", "env_key_instructions", "experimental_bearer_token",
        "requires_openai_auth", "wire_api", "query_params", "http_headers", "env_http_headers",
        "request_max_retries", "stream_max_retries", "stream_idle_timeout_ms",
        "supports_websockets", "supports_standalone_web_search",
        "command", "args", "timeout_ms", "refresh_interval_ms", "cwd"
    ]

    /// Top-level keys CodexBridger is allowed to write into config.toml.
    private static let documentedTopLevelKeys: Set<String> = [
        "model", "model_provider", "model_catalog_json", "model_reasoning_effort",
        "model_reasoning_summary", "model_verbosity", "model_supports_reasoning_summaries"
    ]

    private func makeWriter(_ paths: CodexPaths) -> CodexConfigWriter {
        CodexConfigWriter(
            paths: paths,
            templateSource: StaticCatalogTemplate(),
            now: { CodexConfigWriterTests.fixedDate }
        )
    }

    private func keys(inTable header: String, text: String) -> [String] {
        let lines = text.components(separatedBy: TOMLDocument.newline)
        guard let start = lines.firstIndex(of: header) else { return [] }
        var keys: [String] = []
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("[") { break }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            keys.append(String(trimmed[trimmed.startIndex..<equals]).trimmingCharacters(in: .whitespaces))
        }
        return keys
    }

    private func topLevelKeys(_ text: String) -> [String] {
        var keys: [String] = []
        for line in text.components(separatedBy: TOMLDocument.newline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            keys.append(String(trimmed[trimmed.startIndex..<equals]).trimmingCharacters(in: .whitespaces))
        }
        return keys
    }

    // MARK: - Files and locations

    func testActivationWritesCatalogConfigAndAuthInRequiredLocations() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let provider = TestSupport.sampleProvider(id: "cpa")
        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.configTOML.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.authJSON.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.catalog(for: "cpa").path))
        XCTAssertEqual(result.catalogURL.lastPathComponent, "cpa-model-catalog.json")
        XCTAssertEqual(result.catalogURL.deletingLastPathComponent().lastPathComponent, "model-catalogs")
        XCTAssertEqual(result.catalogURL.deletingLastPathComponent().path, paths.modelCatalogsDirectory.path)
    }

    func testConfigPointsAtTheAbsoluteCatalogPath() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let provider = TestSupport.sampleProvider(id: "cpa")
        _ = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )
        let snapshot = CodexConfigReader(paths: paths).snapshot()
        XCTAssertEqual(snapshot.modelProviderID, "cpa")
        XCTAssertEqual(snapshot.modelSlug, "demo-large")
        XCTAssertEqual(snapshot.modelCatalogJSON, paths.catalog(for: "cpa").path)
        XCTAssertTrue(snapshot.catalogFileExists)
    }

    // MARK: - Only documented keys

    func testProviderTableWritesOnlyDocumentedKeys() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        var provider = TestSupport.sampleProvider(id: "cpa")
        provider.queryParams = ["api-version": "2025-04-01"]
        provider.httpHeaders = ["X-Tenant": "acme"]
        provider.environmentHTTPHeaders = ["X-Features": "ACME_FEATURES"]
        provider.requestMaxRetries = 2
        provider.streamMaxRetries = 3
        provider.streamIdleTimeoutMs = 120_000
        provider.supportsWebsockets = false
        provider.supportsStandaloneWebSearch = true

        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )
        let keys = keys(inTable: "[model_providers.cpa]", text: result.configTOML)
        XCTAssertFalse(keys.isEmpty)
        for key in keys {
            XCTAssertTrue(
                CodexConfigWriterTests.documentedProviderKeys.contains(key),
                "undocumented provider key written to config.toml: " + key
            )
        }
        let topLevel = topLevelKeys(result.configTOML)
        for key in topLevel {
            XCTAssertTrue(
                CodexConfigWriterTests.documentedTopLevelKeys.contains(key),
                "undocumented top-level key written to config.toml: " + key
            )
        }
    }

    func testWireAPIIsAlwaysTheOnlySupportedValue() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let provider = TestSupport.sampleProvider(id: "cpa")
        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )
        XCTAssertTrue(result.configTOML.contains("wire_api = \"responses\""))
        XCTAssertEqual(CodexConfigWriter.wireAPIValue, "responses")
    }

    // MARK: - Backups

    func testBackupsAreTakenBeforeWritingAndHoldTheOriginalContent() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        try AtomicFile.write("approval_policy = \"on-request\"\n", to: paths.configTOML)
        try AtomicFile.write("{\"OPENAI_API_KEY\": \"original\"}\n", to: paths.authJSON)

        let provider = TestSupport.sampleProvider(id: "cpa")
        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )

        let configBackup = try XCTUnwrap(result.backupConfigURL)
        let authBackup = try XCTUnwrap(result.backupAuthURL)
        // The provider segment names the provider the backed-up file belonged to, not the one
        // being activated — the file holds the old provider, so that is what it should be called.
        XCTAssertEqual(configBackup.lastPathComponent, "config-cpa-2026-10-05-1930-bak.toml")
        XCTAssertEqual(authBackup.lastPathComponent, "auth-cpa-2026-10-05-1930-bak.json")
        XCTAssertEqual(configBackup.deletingLastPathComponent().path, paths.backupDirectory.path)
        XCTAssertEqual(authBackup.deletingLastPathComponent().path, paths.backupDirectory.path)
        XCTAssertEqual(try String(contentsOf: configBackup), "approval_policy = \"on-request\"\n")
        XCTAssertEqual(try String(contentsOf: authBackup), "{\"OPENAI_API_KEY\": \"original\"}\n")
    }

    func testFirstActivationOnFreshMachineTakesNoBackup() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let provider = TestSupport.sampleProvider(id: "cpa")
        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )
        XCTAssertNil(result.backupConfigURL)
        XCTAssertNil(result.backupAuthURL)
    }

    // MARK: - Preserving unrelated configuration

    func testUnrelatedConfigContentSurvivesActivation() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let existing = [
            "approval_policy = \"on-request\"",
            "notify = [",
            "    \"/usr/local/bin/notify\",",
            "    'turn-ended'",
            "]",
            "",
            "[desktop]",
            "appearanceTheme = 'light'",
            "",
            "[mcp_servers.exa]",
            "command = '/opt/homebrew/bin/exa-mcp-server'",
            "",
            "[hooks.state.'/Users/me/hooks.json:pre_tool_use:0:0']",
            "trusted_hash = 'sha256:abc123'",
            "",
            "[[skills.config]]",
            "enabled = false"
        ].joined(separator: TOMLDocument.newline) + TOMLDocument.newline
        try AtomicFile.write(existing, to: paths.configTOML)

        let provider = TestSupport.sampleProvider(id: "cpa")
        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )

        for fragment in [
            "approval_policy = \"on-request\"",
            "/usr/local/bin/notify",
            "turn-ended",
            "[desktop]",
            "appearanceTheme = 'light'",
            "[mcp_servers.exa]",
            "/opt/homebrew/bin/exa-mcp-server",
            "[hooks.state.'/Users/me/hooks.json:pre_tool_use:0:0']",
            "sha256:abc123",
            "[[skills.config]]"
        ] {
            XCTAssertTrue(result.configTOML.contains(fragment), "activation destroyed: " + fragment)
        }
    }

    // MARK: - auth.json

    func testAuthJSONCarriesTokenAndPreservesOtherEntries() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        try AtomicFile.write(
            "{\"chatgpt_tokens\": \"keep-me\", \"OPENAI_API_KEY\": \"old-key\"}",
            to: paths.authJSON
        )
        var provider = TestSupport.sampleProvider(id: "cpa")
        provider.bearerToken = "sk-new-token"
        _ = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )

        let auth = try TestSupport.json(paths.authJSON)
        XCTAssertEqual(auth["OPENAI_API_KEY"] as? String, "sk-new-token")
        XCTAssertEqual(auth["CPA_KEY"] as? String, "sk-new-token")
        XCTAssertEqual(auth["auth_mode"] as? String, "apikey")
        XCTAssertEqual(auth["chatgpt_tokens"] as? String, "keep-me", "unrelated credentials must survive")
        XCTAssertEqual(CodexConfigReader(paths: paths).authKeyNames(), ["CPA_KEY", "OPENAI_API_KEY", "auth_mode", "chatgpt_tokens"])
    }

    func testEmptyBearerTokenProducesAWarningAndKeepsExistingKey() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        try AtomicFile.write("{\"OPENAI_API_KEY\": \"keep\"}", to: paths.authJSON)
        var provider = TestSupport.sampleProvider(id: "cpa")
        provider.bearerToken = ""
        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )
        XCTAssertFalse(result.warnings.isEmpty)
        let auth = try TestSupport.json(paths.authJSON)
        XCTAssertEqual(auth["OPENAI_API_KEY"] as? String, "keep")
    }

    // MARK: - Provider rendering

    func testEnvironmentKeyModeWritesNoCredential() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        var provider = TestSupport.sampleProvider(id: "env")
        provider.credentialMode = .environmentKey
        provider.environmentKeyName = "MY_PROVIDER_KEY"
        provider.environmentKeyInstructions = "export MY_PROVIDER_KEY=..."
        provider.bearerToken = ""
        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )
        XCTAssertTrue(result.configTOML.contains("env_key = \"MY_PROVIDER_KEY\""))
        XCTAssertTrue(result.configTOML.contains("env_key_instructions = \"export MY_PROVIDER_KEY=...\""))
        XCTAssertFalse(result.configTOML.contains("experimental_bearer_token"))
    }

    func testCommandAuthRendersSubTable() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        var provider = TestSupport.sampleProvider(id: "cmd")
        provider.credentialMode = .command
        provider.commandAuth = ProviderCommandAuth(
            command: "/usr/local/bin/fetch-token",
            args: ["--audience", "codex"],
            timeoutMs: 5_000,
            refreshIntervalMs: 300_000,
            cwd: "/tmp"
        )
        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )
        XCTAssertTrue(result.configTOML.contains("[model_providers.cmd.auth]"))
        XCTAssertTrue(result.configTOML.contains("command = \"/usr/local/bin/fetch-token\""))
        XCTAssertTrue(result.configTOML.contains("args = [\"--audience\", \"codex\"]"))
        let keys = keys(inTable: "[model_providers.cmd.auth]", text: result.configTOML)
        XCTAssertEqual(keys.sorted(), ["args", "command", "cwd", "refresh_interval_ms", "timeout_ms"])
    }

    func testRequiresOpenAIAuthAndBearerTokenCanCoexist() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        var provider = TestSupport.sampleProvider(id: "cpa")
        provider.requiresOpenAIAuth = true
        provider.bearerToken = "123456"
        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )
        XCTAssertTrue(result.configTOML.contains("requires_openai_auth = true"))
        XCTAssertTrue(result.configTOML.contains("experimental_bearer_token = \"123456\""))
    }

    /// Switching providers removes the previous one from config.toml.
    ///
    /// This test used to assert the opposite — that `[model_providers.one]` survives after
    /// activating `two`. That behaviour left the old provider fully resolvable, address and
    /// bearer token included, and the user reported the leftover table in their real
    /// config.toml. The expectation is inverted deliberately, not relaxed: keeping a dead
    /// provider is the bug, and a test that pinned it would have hidden the fix.
    func testSwitchingProviderRemovesTheEarlierProviderDefinition() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)
        let first = TestSupport.sampleProvider(id: "one")
        let second = TestSupport.sampleProvider(id: "two")
        _ = try writer.activate(provider: first, model: first.models[0], configuration: CodexBridgerConfiguration())
        let result = try writer.activate(
            provider: second, model: second.models[1], configuration: CodexBridgerConfiguration()
        )
        XCTAssertFalse(
            result.configTOML.contains("[model_providers.one]"),
            "the replaced provider must be removed, got:\n" + result.configTOML
        )
        XCTAssertTrue(result.configTOML.contains("[model_providers.two]"))
        XCTAssertEqual(CodexConfigReader(paths: paths).snapshot().modelProviderID, "two")
        XCTAssertEqual(CodexConfigReader(paths: paths).snapshot().modelSlug, "demo-small")
    }

    func testReactivationProducesIdenticalConfig() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let writer = makeWriter(paths)
        let provider = TestSupport.sampleProvider(id: "cpa")
        let first = try writer.activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )
        let second = try writer.activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )
        XCTAssertEqual(first.configTOML, second.configTOML)
        XCTAssertEqual(first.catalogJSON, second.catalogJSON)
        XCTAssertEqual(first.authJSON, second.authJSON)
    }

    func testConfiguredReasoningSettingsAreHonored() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        var configuration = CodexBridgerConfiguration()
        configuration.modelReasoningEffort = .ultra
        configuration.modelReasoningSummary = .detailed
        configuration.modelVerbosity = .high
        configuration.modelSupportsReasoningSummaries = true
        let provider = TestSupport.sampleProvider(id: "cpa")
        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: configuration
        )
        XCTAssertTrue(result.configTOML.contains("model_reasoning_effort = \"ultra\""))
        XCTAssertTrue(result.configTOML.contains("model_reasoning_summary = \"detailed\""))
        XCTAssertTrue(result.configTOML.contains("model_verbosity = \"high\""))
        XCTAssertTrue(result.configTOML.contains("model_supports_reasoning_summaries = true"))
    }

    func testModelDefaultEffortIsUsedWhenNothingIsConfigured() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let provider = TestSupport.sampleProvider(id: "cpa")
        let result = try makeWriter(paths).activate(
            provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
        )
        XCTAssertTrue(result.configTOML.contains("model_reasoning_effort = \"high\""))
    }

    // MARK: - Rejections

    func testRejectsUnsafeProviderIdentifiers() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        for bad in ["has.dot", "has space", "", "has/slash"] {
            var provider = TestSupport.sampleProvider(id: bad)
            provider.id = bad
            XCTAssertThrowsError(
                try makeWriter(paths).activate(
                    provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
                ),
                "provider id must be rejected: " + bad
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configTOML.path),
                       "nothing may be written when validation fails")
    }

    func testRejectsMissingBaseURL() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        var provider = TestSupport.sampleProvider(id: "cpa")
        provider.baseURL = "   "
        XCTAssertThrowsError(
            try makeWriter(paths).activate(
                provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
            )
        )
    }

    func testRejectsCommandAuthWithoutCommand() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        var provider = TestSupport.sampleProvider(id: "cpa")
        provider.credentialMode = .command
        provider.commandAuth = ProviderCommandAuth(command: "")
        XCTAssertThrowsError(
            try makeWriter(paths).activate(
                provider: provider, model: provider.models[0], configuration: CodexBridgerConfiguration()
            )
        )
    }
}
