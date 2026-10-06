import Foundation

// MARK: - Values that Codex defines

/// Reasoning levels accepted by model_reasoning_effort and by a catalog entry
/// supported_reasoning_levels.
///
/// The set comes from the official configuration reference, which documents
/// model_reasoning_effort as "such as low, medium, high, xhigh, max, or ultra".
/// Codex tolerates unknown strings here, but CodexBridger only offers documented
/// values so a written config can never carry an effort Codex does not advertise.
public enum ReasoningEffort: String, Codable, CaseIterable, Sendable, Comparable {
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    public static let all: [ReasoningEffort] = [.low, .medium, .high, .xhigh, .max, .ultra]

    public static func < (lhs: ReasoningEffort, rhs: ReasoningEffort) -> Bool {
        let order = ReasoningEffort.all
        let l = order.firstIndex(of: lhs) ?? 0
        let r = order.firstIndex(of: rhs) ?? 0
        return l < r
    }
}

/// model_reasoning_summary.
public enum ReasoningSummary: String, Codable, CaseIterable, Sendable {
    case auto
    case concise
    case detailed
    case none
}

/// model_verbosity.
public enum ModelVerbosity: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

/// Whether a catalog model is offered in the Codex model picker.
public enum ModelVisibility: String, Codable, CaseIterable, Sendable {
    case list
    case hide
}

/// How a provider authenticates.
///
/// The official reference states that model_providers.<id>.auth must not be
/// combined with env_key, experimental_bearer_token, or requires_openai_auth,
/// so these modes are mutually exclusive.
public enum ProviderCredentialMode: String, Codable, CaseIterable, Sendable {
    case none
    case bearerToken
    case environmentKey
    case command

    public var displayName: String {
        switch self {
        case .none: return "无凭据（自带认证的本地服务）"
        case .bearerToken: return "Bearer Token（experimental_bearer_token）"
        case .environmentKey: return "环境变量（env_key）"
        case .command: return "外部命令取 Token（.auth）"
        }
    }
}

// MARK: - Persisted configuration

/// One model offered by a provider.
public struct ModelConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Catalog slug and the value written to config.toml model.
    public var slug: String
    /// Catalog display_name.
    public var displayName: String
    /// Catalog description.
    public var modelDescription: String
    /// Catalog context_window.
    public var contextWindow: Int
    /// Catalog max_context_window.
    public var maxContextWindow: Int
    /// Catalog supported_reasoning_levels.
    public var supportedReasoningEfforts: [ReasoningEffort]
    /// Catalog default_reasoning_level.
    public var defaultReasoningEffort: ReasoningEffort
    /// Catalog visibility.
    public var visibility: ModelVisibility
    /// Catalog priority, used to order the model picker.
    public var priority: Int

    public init(
        id: UUID = UUID(),
        slug: String,
        displayName: String,
        modelDescription: String = "",
        contextWindow: Int = 128_000,
        maxContextWindow: Int = 128_000,
        supportedReasoningEfforts: [ReasoningEffort] = ReasoningEffort.all,
        defaultReasoningEffort: ReasoningEffort = .medium,
        visibility: ModelVisibility = .list,
        priority: Int = 1
    ) {
        self.id = id
        self.slug = slug
        self.displayName = displayName
        self.modelDescription = modelDescription
        self.contextWindow = contextWindow
        self.maxContextWindow = maxContextWindow
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.defaultReasoningEffort = defaultReasoningEffort
        self.visibility = visibility
        self.priority = priority
    }
}

/// Command-backed bearer token configuration (model_providers.<id>.auth).
public struct ProviderCommandAuth: Codable, Equatable, Sendable {
    public var command: String
    public var args: [String]
    public var timeoutMs: Int?
    public var refreshIntervalMs: Int?
    public var cwd: String?

    public init(
        command: String = "",
        args: [String] = [],
        timeoutMs: Int? = nil,
        refreshIntervalMs: Int? = nil,
        cwd: String? = nil
    ) {
        self.command = command
        self.args = args
        self.timeoutMs = timeoutMs
        self.refreshIntervalMs = refreshIntervalMs
        self.cwd = cwd
    }
}

/// One third-party model provider, mirroring [model_providers.<id>].
///
/// Every stored field maps to a key documented in the Codex configuration
/// reference. Nothing Codex does not support is persisted.
public struct ProviderConfiguration: Codable, Identifiable, Equatable, Sendable {
    /// Provider id: used as [model_providers.<id>] and in the catalog file name.
    /// Restricted to bare TOML key characters so it never needs quoting.
    public var id: String
    public var name: String
    /// Sidebar group. CodexBridger own metadata: it is never written to config.toml.
    public var category: String
    public var baseURL: String

    public var credentialMode: ProviderCredentialMode
    /// requires_openai_auth. Independent of the credential source: a provider may
    /// take its bearer token from config while still being treated as OpenAI-auth.
    public var requiresOpenAIAuth: Bool
    /// Used by .bearerToken; also mirrored into auth.json.
    public var bearerToken: String
    /// Used by .environmentKey.
    public var environmentKeyName: String
    public var environmentKeyInstructions: String
    public var commandAuth: ProviderCommandAuth

    /// query_params
    public var queryParams: [String: String]
    /// http_headers
    public var httpHeaders: [String: String]
    /// env_http_headers (header name -> environment variable name)
    public var environmentHTTPHeaders: [String: String]
    /// request_max_retries
    public var requestMaxRetries: Int?
    /// stream_max_retries
    public var streamMaxRetries: Int?
    /// stream_idle_timeout_ms
    public var streamIdleTimeoutMs: Int?
    /// supports_websockets
    public var supportsWebsockets: Bool?
    /// supports_standalone_web_search
    public var supportsStandaloneWebSearch: Bool?

    public var models: [ModelConfiguration]

    public init(
        id: String,
        name: String,
        baseURL: String,
        category: String = ProviderPreset.customCategory,
        credentialMode: ProviderCredentialMode = .none,
        requiresOpenAIAuth: Bool = false,
        bearerToken: String = "",
        environmentKeyName: String = "",
        environmentKeyInstructions: String = "",
        commandAuth: ProviderCommandAuth = ProviderCommandAuth(),
        queryParams: [String: String] = [:],
        httpHeaders: [String: String] = [:],
        environmentHTTPHeaders: [String: String] = [:],
        requestMaxRetries: Int? = nil,
        streamMaxRetries: Int? = nil,
        streamIdleTimeoutMs: Int? = nil,
        supportsWebsockets: Bool? = nil,
        supportsStandaloneWebSearch: Bool? = nil,
        models: [ModelConfiguration] = []
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.category = category
        self.credentialMode = credentialMode
        self.requiresOpenAIAuth = requiresOpenAIAuth
        self.bearerToken = bearerToken
        self.environmentKeyName = environmentKeyName
        self.environmentKeyInstructions = environmentKeyInstructions
        self.commandAuth = commandAuth
        self.queryParams = queryParams
        self.httpHeaders = httpHeaders
        self.environmentHTTPHeaders = environmentHTTPHeaders
        self.requestMaxRetries = requestMaxRetries
        self.streamMaxRetries = streamMaxRetries
        self.streamIdleTimeoutMs = streamIdleTimeoutMs
        self.supportsWebsockets = supportsWebsockets
        self.supportsStandaloneWebSearch = supportsStandaloneWebSearch
        self.models = models
    }

    /// Provider ids must be usable as a bare TOML key and as a file name stem.
    public static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

/// The whole persisted state of the app, stored in ~/.codex/codexbridger/config.json.
public struct CodexBridgerConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var providers: [ProviderConfiguration]
    /// The provider currently written into config.toml, if any.
    public var activeProviderID: String?
    /// The model currently written into config.toml, if any.
    public var activeModelSlug: String?

    // Documented top-level settings CodexBridger is allowed to manage.
    public var modelReasoningEffort: ReasoningEffort?
    public var modelReasoningSummary: ReasoningSummary?
    public var modelVerbosity: ModelVerbosity?
    public var modelSupportsReasoningSummaries: Bool?

    /// Catalog entry used as the structural template when generating a catalog.
    public var catalogTemplateSlug: String

    /// Re-read the written files after activating and report any mismatch.
    public var verifyAfterWrite: Bool

    /// Language the interface is drawn in. Not a Codex setting — stored beside the providers so
    /// the choice survives a restart.
    public var interfaceLanguage: InterfaceLanguage

    public static let currentSchemaVersion = 1

    public init(
        schemaVersion: Int = CodexBridgerConfiguration.currentSchemaVersion,
        providers: [ProviderConfiguration] = [],
        activeProviderID: String? = nil,
        activeModelSlug: String? = nil,
        modelReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary? = nil,
        modelVerbosity: ModelVerbosity? = nil,
        modelSupportsReasoningSummaries: Bool? = nil,
        catalogTemplateSlug: String = "gpt-5.5",
        verifyAfterWrite: Bool = true,
        interfaceLanguage: InterfaceLanguage = .system
    ) {
        self.schemaVersion = schemaVersion
        self.providers = providers
        self.activeProviderID = activeProviderID
        self.activeModelSlug = activeModelSlug
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelVerbosity = modelVerbosity
        self.modelSupportsReasoningSummaries = modelSupportsReasoningSummaries
        self.catalogTemplateSlug = catalogTemplateSlug
        self.verifyAfterWrite = verifyAfterWrite
        self.interfaceLanguage = interfaceLanguage
    }

    public func provider(id: String) -> ProviderConfiguration? {
        providers.first { $0.id == id }
    }
}
