import Foundation

// MARK: - Tolerant decoding
//
// Synthesized Codable requires every key to be present, even when the property declares a
// default. That made one hand-edited or partially written key enough to fail the entire
// file, and the UI then showed an empty provider list — indistinguishable from losing the
// data. These decoders fill missing keys from the same defaults the initialisers use.
//
// The split is deliberate:
//   * a missing key or a mistyped scalar  -> fall back to the default (recoverable),
//   * a corrupt structure (providers/models not an array) -> throw, so the UI can say so.
// Turning structural corruption into an empty list is exactly the silent-data-loss
// failure this file exists to prevent.

private extension KeyedDecodingContainer {
    /// Decodes a value, using the fallback when the key is absent or unreadable.
    func lenient<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? fallback
    }

    /// Decodes an optional value, treating an unreadable value as absent.
    func lenientOptional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)).flatMap { $0 }
    }
}

// MARK: - ModelConfiguration

extension ModelConfiguration {
    enum CodingKeys: String, CodingKey {
        case id, slug, displayName, modelDescription, contextWindow, maxContextWindow
        case supportedReasoningEfforts, defaultReasoningEffort, visibility, priority
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let slug: String = container.lenient(.slug, default: "")
        self.id = container.lenient(.id, default: UUID())
        self.slug = slug
        // A model with no display name is shown under its slug, matching how new models
        // are created in the UI.
        self.displayName = container.lenient(.displayName, default: slug)
        self.modelDescription = container.lenient(.modelDescription, default: "")
        self.contextWindow = container.lenient(.contextWindow, default: 128_000)
        self.maxContextWindow = container.lenient(.maxContextWindow, default: 128_000)
        self.supportedReasoningEfforts = container.lenient(
            .supportedReasoningEfforts, default: ReasoningEffort.all
        )
        self.defaultReasoningEffort = container.lenient(.defaultReasoningEffort, default: .medium)
        self.visibility = container.lenient(.visibility, default: .list)
        self.priority = container.lenient(.priority, default: 1)
    }
}

// MARK: - ProviderCommandAuth

extension ProviderCommandAuth {
    enum CodingKeys: String, CodingKey {
        case command, args, timeoutMs, refreshIntervalMs, cwd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.command = container.lenient(.command, default: "")
        self.args = container.lenient(.args, default: [])
        self.timeoutMs = container.lenientOptional(.timeoutMs)
        self.refreshIntervalMs = container.lenientOptional(.refreshIntervalMs)
        self.cwd = container.lenientOptional(.cwd)
    }
}

// MARK: - ProviderConfiguration

extension ProviderConfiguration {
    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, category, credentialMode, requiresOpenAIAuth, bearerToken
        case environmentKeyName, environmentKeyInstructions, commandAuth
        case queryParams, httpHeaders, environmentHTTPHeaders
        case requestMaxRetries, streamMaxRetries, streamIdleTimeoutMs
        case supportsWebsockets, supportsStandaloneWebSearch, models
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = container.lenient(.id, default: "")
        self.name = container.lenient(.name, default: "")
        self.baseURL = container.lenient(.baseURL, default: "")
        self.category = container.lenient(.category, default: ProviderPreset.customCategory)
        self.credentialMode = container.lenient(.credentialMode, default: .none)
        self.requiresOpenAIAuth = container.lenient(.requiresOpenAIAuth, default: false)
        self.bearerToken = container.lenient(.bearerToken, default: "")
        self.environmentKeyName = container.lenient(.environmentKeyName, default: "")
        self.environmentKeyInstructions = container.lenient(
            .environmentKeyInstructions, default: ""
        )
        self.commandAuth = container.lenient(.commandAuth, default: ProviderCommandAuth())
        self.queryParams = container.lenient(.queryParams, default: [:])
        self.httpHeaders = container.lenient(.httpHeaders, default: [:])
        self.environmentHTTPHeaders = container.lenient(.environmentHTTPHeaders, default: [:])
        self.requestMaxRetries = container.lenientOptional(.requestMaxRetries)
        self.streamMaxRetries = container.lenientOptional(.streamMaxRetries)
        self.streamIdleTimeoutMs = container.lenientOptional(.streamIdleTimeoutMs)
        self.supportsWebsockets = container.lenientOptional(.supportsWebsockets)
        self.supportsStandaloneWebSearch = container.lenientOptional(
            .supportsStandaloneWebSearch
        )
        if container.contains(.models) {
            self.models = try container.decode([ModelConfiguration].self, forKey: .models)
        } else {
            self.models = []
        }
    }
}

// MARK: - CodexBridgerConfiguration

extension CodexBridgerConfiguration {
    enum CodingKeys: String, CodingKey {
        case schemaVersion, providers, activeProviderID, activeModelSlug
        case modelReasoningEffort, modelReasoningSummary, modelVerbosity
        case modelSupportsReasoningSummaries, catalogTemplateSlug, verifyAfterWrite
        case interfaceLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = container.lenient(
            .schemaVersion, default: CodexBridgerConfiguration.currentSchemaVersion
        )
        if container.contains(.providers) {
            // Structural corruption must throw: silently pruning to an empty list would
            // look to the user like their providers were deleted.
            self.providers = try container.decode(
                [ProviderConfiguration].self, forKey: .providers
            )
        } else {
            self.providers = []
        }
        self.activeProviderID = container.lenientOptional(.activeProviderID)
        self.activeModelSlug = container.lenientOptional(.activeModelSlug)
        self.modelReasoningEffort = container.lenientOptional(.modelReasoningEffort)
        self.modelReasoningSummary = container.lenientOptional(.modelReasoningSummary)
        self.modelVerbosity = container.lenientOptional(.modelVerbosity)
        self.modelSupportsReasoningSummaries = container.lenientOptional(
            .modelSupportsReasoningSummaries
        )
        self.catalogTemplateSlug = container.lenient(.catalogTemplateSlug, default: "gpt-5.5")
        self.verifyAfterWrite = container.lenient(.verifyAfterWrite, default: true)
        // Absent in configs written before the setting existed; `system` is the safe default.
        self.interfaceLanguage = container.lenient(
            .interfaceLanguage, default: InterfaceLanguage.system
        )
    }
}
