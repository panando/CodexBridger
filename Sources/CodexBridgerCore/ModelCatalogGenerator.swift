import Foundation

/// Builds the JSON body of <provider>-model-catalog.json.
public struct ModelCatalogGenerator {
    public let templateSource: CatalogTemplateSource

    public init(templateSource: CatalogTemplateSource) {
        self.templateSource = templateSource
    }

    public static let defaultContextWindow = 128_000

    /// Wording Codex itself ships for each reasoning level.
    public static func effortDescription(_ effort: String) -> String {
        switch effort {
        case "low": return "Fast responses with lighter reasoning"
        case "medium": return "Balances speed and reasoning depth for everyday tasks"
        case "high": return "Greater reasoning depth for complex problems"
        case "xhigh": return "Extra high reasoning depth for complex problems"
        case "max": return "Maximum reasoning depth for the hardest problems"
        case "ultra": return "Maximum reasoning with automatic task delegation"
        default: return effort
        }
    }

    public enum GenerationError: Error, LocalizedError, Equatable {
        case noModels(providerID: String)
        case emptySlug(providerID: String)
        case duplicateSlug(slug: String)
        case invalidContextWindow(slug: String)
        case noUsableTemplate
        case templateMissingInstructions

        public var errorDescription: String? {
            switch self {
            case let .noModels(providerID):
                return "提供商 " + providerID + " 还没有配置任何模型"
            case let .emptySlug(providerID):
                return "提供商 " + providerID + " 存在空的模型 slug"
            case let .duplicateSlug(slug):
                return "存在重复的模型 slug: " + slug
            case let .invalidContextWindow(slug):
                return "模型 " + slug + " 的上下文窗口必须大于 0"
            case .noUsableTemplate:
                return "没有可用的模型目录模板"
            case .templateMissingInstructions:
                return "模板缺少 base_instructions 或 model_messages.instructions_template"
            }
        }
    }

    /// Produces the whole catalog object, i.e. what gets written to disk.
    public func makeCatalog(
        provider: ProviderConfiguration,
        preferredTemplateSlug: String
    ) throws -> [String: Any] {
        guard !provider.models.isEmpty else { throw GenerationError.noModels(providerID: provider.id) }
        var seen = Set<String>()
        for model in provider.models {
            let slug = model.slug.trimmingCharacters(in: .whitespacesAndNewlines)
            if slug.isEmpty { throw GenerationError.emptySlug(providerID: provider.id) }
            if !seen.insert(slug).inserted { throw GenerationError.duplicateSlug(slug: slug) }
            if model.contextWindow <= 0 { throw GenerationError.invalidContextWindow(slug: slug) }
        }
        guard var template = try templateSource.templateEntry(preferredSlug: preferredTemplateSlug),
              !template.isEmpty else { throw GenerationError.noUsableTemplate }
        guard template["base_instructions"] != nil || hasInstructionsTemplate(template) else {
            throw GenerationError.templateMissingInstructions
        }
        // The template slug is only structural; it must never leak into output.
        template["slug"] = provider.models[0].slug

        let entries = try provider.models.enumerated().map { index, model in
            try makeEntry(model: model, template: template, priority: index)
        }
        return ["models": entries]
    }

    private func hasInstructionsTemplate(_ template: [String: Any]) -> Bool {
        guard let messages = template["model_messages"] as? [String: Any] else { return false }
        if let value = messages["instructions_template"] as? String, !value.isEmpty { return true }
        return false
    }

    /// Copies the template and overrides only the parameters the user configured.
    public func makeEntry(
        model: ModelConfiguration,
        template: [String: Any],
        priority: Int
    ) throws -> [String: Any] {
        var entry = template
        let contextWindow = max(model.contextWindow, 1)
        let maxContextWindow = max(model.maxContextWindow, contextWindow)
        let efforts = model.supportedReasoningEfforts.isEmpty
            ? [model.defaultReasoningEffort]
            : model.supportedReasoningEfforts
        let defaultEffort = efforts.contains(model.defaultReasoningEffort)
            ? model.defaultReasoningEffort
            : efforts[0]

        entry["slug"] = model.slug
        entry["display_name"] = model.displayName.isEmpty ? model.slug : model.displayName
        entry["description"] = model.modelDescription.isEmpty ? model.displayName : model.modelDescription
        entry["context_window"] = contextWindow
        entry["max_context_window"] = maxContextWindow
        entry["default_reasoning_level"] = defaultEffort.rawValue
        entry["supported_reasoning_levels"] = efforts.map { effort in
            ["effort": effort.rawValue, "description": ModelCatalogGenerator.effortDescription(effort.rawValue)]
        }
        entry["visibility"] = model.visibility.rawValue
        entry["priority"] = 1000 + priority
        return entry
    }

    /// Serialises the catalog the way Codex expects it: a pretty-printed object
    /// with a sorted key order so repeated activations produce identical bytes.
    public static func serialize(_ catalog: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: catalog,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard var text = String(data: data, encoding: .utf8) else {
            throw GenerationError.noUsableTemplate
        }
        if !text.hasSuffix(TOMLDocument.newline) { text += TOMLDocument.newline }
        return text
    }
}
