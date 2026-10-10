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
    /// Catalog auto_review_model_override: the model slug the auto-review
    /// sub-agent runs on. nil means the key is not written and Codex falls
    /// back to reviewing with the active model itself. Only some models
    /// accept the strict JSON schema the reviewer needs, so this is chosen
    /// per provider, never per model.
    public var autoReviewModelOverride: String?

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
        priority: Int = 1,
        autoReviewModelOverride: String? = nil
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
        self.autoReviewModelOverride = autoReviewModelOverride
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

    /// auto_review_model_override written into every catalog entry of this
    /// provider. Stored on the provider, not per model: the reviewer model is
    /// one choice for the whole provider. nil = do not write the key.
    public var autoReviewModelOverride: String?

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
        autoReviewModelOverride: String? = nil,
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
        self.autoReviewModelOverride = autoReviewModelOverride
        self.models = models
    }

    /// Provider ids must be usable as a bare TOML key and as a file name stem.
    public static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

extension ProviderConfiguration {
    /// Everything that reaches `config.toml` or `auth.json`, compared field by field.
    ///
    /// The model list and the provider id are deliberately excluded: the models are published in
    /// the model parameter file, and the id is compared separately because a rename changes the
    /// file the id names. `category` never leaves this app.
    ///
    /// Saving a provider only rewrites the model parameter file, so this is what tells a save
    /// whether the change is something a catalog write can carry or something that needs a full
    /// re-activation.
    public func hasSamePublishedSettings(as other: ProviderConfiguration) -> Bool {
        var lhs = self
        var rhs = other
        lhs.id = ""
        rhs.id = ""
        lhs.category = ""
        rhs.category = ""
        lhs.models = []
        rhs.models = []
        return lhs == rhs
    }

    /// Whether the files would be written from exactly this provider.
    ///
    /// `hasSamePublishedSettings` above deliberately ignores the model list and the id, because
    /// it answers a narrower question (can a catalog write alone carry this change?). This one
    /// answers "is what is on disk already this?", so both count: the catalog carries the
    /// models, and a renamed id names a different table and a different file. `category` never
    /// leaves this app, so changing it is not a reason to write anything.
    public func hasSameAppliedState(as other: ProviderConfiguration) -> Bool {
        var lhs = self
        var rhs = other
        lhs.category = ""
        rhs.category = ""
        return lhs == rhs
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
    /// The provider as it was last written to the files, kept so the screen can tell whether the
    /// button still has anything to apply. Set by every activation; absent in configs written
    /// before it existed, which simply means "nothing has been applied since this was added".
    public var publishedProvider: ProviderConfiguration?

    // Documented top-level settings CodexBridger is allowed to manage.
    public var modelReasoningEffort: ReasoningEffort?
    public var modelReasoningSummary: ReasoningSummary?
    public var modelVerbosity: ModelVerbosity?
    public var modelSupportsReasoningSummaries: Bool?

    /// Catalog entry used as the structural template when generating a catalog.
    public var catalogTemplateSlug: String

    /// Last 一键检测 result per provider id. Credential-free by construction:
    /// see AutoReviewScanCache.
    public var autoReviewScans: [String: AutoReviewScanCache]

    /// Per-model response_format.json_schema.strict values observed from the
    /// harness. A model with no entry is probed with strict=true.
    public var autoReviewStrictOverrides: AutoReviewStrictOverrides

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
        publishedProvider: ProviderConfiguration? = nil,
        modelReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary? = nil,
        modelVerbosity: ModelVerbosity? = nil,
        modelSupportsReasoningSummaries: Bool? = nil,
        catalogTemplateSlug: String = "gpt-5.5",
        autoReviewScans: [String: AutoReviewScanCache] = [:],
        autoReviewStrictOverrides: AutoReviewStrictOverrides = .default,
        verifyAfterWrite: Bool = true,
        interfaceLanguage: InterfaceLanguage = .system
    ) {
        self.schemaVersion = schemaVersion
        self.providers = providers
        self.activeProviderID = activeProviderID
        self.activeModelSlug = activeModelSlug
        self.publishedProvider = publishedProvider
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelVerbosity = modelVerbosity
        self.modelSupportsReasoningSummaries = modelSupportsReasoningSummaries
        self.catalogTemplateSlug = catalogTemplateSlug
        self.autoReviewScans = autoReviewScans
        self.autoReviewStrictOverrides = autoReviewStrictOverrides
        self.verifyAfterWrite = verifyAfterWrite
        self.interfaceLanguage = interfaceLanguage
    }

    public func provider(id: String) -> ProviderConfiguration? {
        providers.first { $0.id == id }
    }
}
