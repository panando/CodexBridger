import Foundation

// MARK: - Preset catalogue
//
// The reference window lists known providers grouped by family, and its primary call to
// action is "新建提供商". These presets are what turn that into one click instead of a blank
// form.
//
// Scope is deliberate: a preset ships only when its OpenAI-compatible endpoint could be
// confirmed against provider documentation. Providers whose base URL is account- or
// region-scoped (for example Aliyun Model Studio, which embeds a workspace id) are left
// out on purpose rather than shipped with a URL that would fail. Model names and context
// windows still have to be confirmed by the user against the provider docs, and every note
// says so.

/// One model offered by a preset, with the context window its provider documents.
///
/// Context is per model, not per provider: DeepSeek-V4 and kimi-k2.7-code are 1M and 256K
/// respectively, while MiniMax ships both 1M and 200K models on one endpoint. A single shared
/// value would truncate one of them.
public struct PresetModel: Equatable, Sendable {
    public let slug: String
    public let contextWindow: Int

    public init(slug: String, contextWindow: Int) {
        self.slug = slug
        self.contextWindow = contextWindow
    }
}

/// A known provider, used to prefill a new entry.
public struct ProviderPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// Sidebar group. Mirrors the reference, which lists "Chat Completions 供应商" etc.
    public let category: String
    public let baseURL: String
    public let credentialMode: ProviderCredentialMode
    public let requiresOpenAIAuth: Bool
    /// Suggested models with their documented context windows. Empty when only the user can
    /// know them, e.g. a blank custom provider.
    public let models: [PresetModel]

    /// Slug list for callers that only care about names.
    public var modelSlugs: [String] { models.map(\.slug) }
    public let note: String
    /// Where baseURL was confirmed, kept so the table in the docs stays auditable.
    public let source: String

    public init(
        id: String,
        name: String,
        category: String,
        baseURL: String,
        credentialMode: ProviderCredentialMode,
        requiresOpenAIAuth: Bool = false,
        models: [PresetModel] = [],
        note: String,
        source: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.baseURL = baseURL
        self.credentialMode = credentialMode
        self.requiresOpenAIAuth = requiresOpenAIAuth
        self.models = models
        self.note = note
        self.source = source
    }

    /// Category used by providers that were not created from a preset.
    public static let customCategory = "自定义"

    public var suggestsModels: Bool { !models.isEmpty }

    /// Builds a provider from this preset. Credentials are never prefilled.
    public func makeProvider(id: String) -> ProviderConfiguration {
        var models: [ModelConfiguration] = []
        // Iterate `self.models`: the local `models` accumulator is empty here, so iterating it
        // would silently produce a provider with no models at all.
        for (index, presetModel) in self.models.enumerated() {
            models.append(
                ModelConfiguration(
                    slug: presetModel.slug,
                    displayName: presetModel.slug,
                    contextWindow: presetModel.contextWindow,
                    maxContextWindow: presetModel.contextWindow,
                    supportedReasoningEfforts: ReasoningEffort.all,
                    defaultReasoningEffort: .medium,
                    priority: index + 1
                )
            )
        }
        return ProviderConfiguration(
            id: id,
            name: name,
            baseURL: baseURL,
            category: category,
            credentialMode: credentialMode,
            requiresOpenAIAuth: requiresOpenAIAuth,
            models: models
        )
    }

    // MARK: - Catalogue

    public static let builtIn: [ProviderPreset] = [
        ProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            category: "常用云服务",
            baseURL: "https://api.deepseek.com",
            credentialMode: .bearerToken,
            models: [
                PresetModel(slug: "deepseek-v4-pro", contextWindow: 1048576),
                PresetModel(slug: "deepseek-flash", contextWindow: 1048576)
            ],
            note: "在 DeepSeek 开放平台创建 API Key 后填到这里。",
            source: "api-docs.deepseek.com/zh-cn/quick_start/pricing（模型名 deepseek-flash / deepseek-v4-pro，上下文 1M，最大输出 384K）"
        ),
        ProviderPreset(
            id: "moonshot-cn",
            name: "Moonshot 月之暗面（国内站）",
            category: "常用云服务",
            baseURL: "https://api.moonshot.cn/v1",
            credentialMode: .bearerToken,
            models: [
                PresetModel(slug: "kimi-k3", contextWindow: 1048576),
                PresetModel(slug: "kimi-k2.7-code", contextWindow: 262144),
                PresetModel(slug: "kimi-k2.7-code-highspeed", contextWindow: 262144)
            ],
            note: "在月之暗面开放平台创建 API Key。kimi-k3 始终思考，可用 low / high / max。",
            source: "platform.kimi.com/docs/guide/kimi-k3-quickstart（kimi-k3 上下文 1M）；kimi-k2-7-code-quickstart（kimi-k2.7-code 上下文 256K）"
        ),
        ProviderPreset(
            id: "minimax-cn",
            name: "MiniMax（国内站）",
            category: "常用云服务",
            baseURL: "https://api.minimax.cn/v1",
            credentialMode: .bearerToken,
            models: [
                PresetModel(slug: "MiniMax-M3", contextWindow: 1048576),
                PresetModel(slug: "MiniMax-M3.1-Flash-Preview", contextWindow: 1048576),
                PresetModel(slug: "MiniMax-M2.7", contextWindow: 204800)
            ],
            note: "在 MiniMax 开放平台创建 API Key。M3.1-Flash-Preview 目前仅 M 套餐与 MiniMax Code 可用。",
            source: "platform.minimax.io/docs/guides/models-intro（M3 / M3.1-Flash-Preview 上下文 1M）；M2.7 上下文 200K"
        ),
        ProviderPreset(
            id: "zhipu",
            name: "智谱 GLM",
            category: "常用云服务",
            baseURL: "https://open.bigmodel.cn/api/coding/paas/v4",
            credentialMode: .bearerToken,
            models: [
                PresetModel(slug: "glm-5.3", contextWindow: 1048576),
                PresetModel(slug: "glm-5.3-flash", contextWindow: 1048576)
            ],
            note: "这是 Coding Plan 的地址，普通开放平台账号的地址不同。GLM-5.3 最大输出 128K。",
            source: "docs.bigmodel.cn/cn/coding-plan/latest-model（Coding Plan 支持 GLM-5.3 / 5.3-Flash，端点 /api/coding/paas/v4）；模型概览（上下文 1M）"
        ),
        ProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            category: "聚合平台",
            baseURL: "https://openrouter.ai/api/v1",
            credentialMode: .bearerToken,
            models: [
                PresetModel(slug: "deepseek/deepseek-v4-pro", contextWindow: 1048576),
                PresetModel(slug: "moonshotai/kimi-k3", contextWindow: 1048576)
            ],
            note: "模型名是「厂商/模型」形式。OpenRouter 有 400+ 模型，可直接问它的 /models 接口看当前可用的。",
            source: "openrouter.ai/api/v1/models（实测：deepseek/deepseek-v4-pro 与 moonshotai/kimi-k3 上下文均为 1048576）"
        )
    ]

    /// Groups presets by category, in catalogue order, dropping empty groups.
    public static func groups(_ presets: [ProviderPreset]) -> [ProviderPresetGroup] {
        var order: [String] = []
        var buckets: [String: [ProviderPreset]] = [:]
        for preset in presets {
            if buckets[preset.category] == nil {
                order.append(preset.category)
                buckets[preset.category] = []
            }
            buckets[preset.category]?.append(preset)
        }
        return order.compactMap { category in
            guard let presets = buckets[category], !presets.isEmpty else { return nil }
            return ProviderPresetGroup(category: category, presets: presets)
        }
    }
}

public struct ProviderPresetGroup: Identifiable, Equatable, Sendable {
    public var id: String { category }
    public let category: String
    public let presets: [ProviderPreset]

    public init(category: String, presets: [ProviderPreset]) {
        self.category = category
        self.presets = presets
    }
}
