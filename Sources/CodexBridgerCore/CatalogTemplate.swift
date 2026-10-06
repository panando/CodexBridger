import Foundation

/// Supplies one known-good catalog entry to use as the structural template.
///
/// Codex validates model_catalog_json strictly, so synthesising an entry from
/// scratch would mean guessing which fields the running build requires. Instead
/// CodexBridger copies a template that Codex itself produced and overrides only
/// the user-facing parameters.
public protocol CatalogTemplateSource: Sendable {
    /// Human readable description of where the template came from.
    var sourceDescription: String { get }
    func templateEntry(preferredSlug: String) throws -> [String: Any]?
}

/// Template captured from "codex debug models --bundled" for the running build.
public struct CodexCLICatalogTemplate: CatalogTemplateSource {
    public let cli: CodexCLI

    public init(cli: CodexCLI) { self.cli = cli }

    public var sourceDescription: String { "ChatGPT CLI (" + cli.executableURL.path + ")" }

    public func templateEntry(preferredSlug: String) throws -> [String: Any]? {
        let object = try cli.bundledCatalog()
        guard let models = object["models"] as? [[String: Any]], !models.isEmpty else {
            return nil
        }
        if let match = models.first(where: { ($0["slug"] as? String) == preferredSlug }) {
            return match
        }
        return models[0]
    }
}

/// A built-in template whose exact field set was verified against Codex.
///
/// These fields are the minimum the running Codex build accepts; each one was
/// discovered by writing a candidate catalog and reading the validator error back
/// (see tools/discover_catalog_schema.py).
public struct StaticCatalogTemplate: CatalogTemplateSource {
    public init() {}

    public var sourceDescription: String { "内置模板（已用 ChatGPT 校验）" }

    public static func reasoningLevels(_ efforts: [String]) -> [[String: String]] {
        efforts.map { ["effort": $0, "description": ModelCatalogGenerator.effortDescription($0)] }
    }

    public func templateEntry(preferredSlug: String) throws -> [String: Any]? {
        [
            "slug": preferredSlug,
            "display_name": preferredSlug,
            "description": "CodexBridger generated model.",
            "supported_reasoning_levels": StaticCatalogTemplate.reasoningLevels([
                "low", "medium", "high", "xhigh", "max", "ultra"
            ]),
            "shell_type": "shell_command",
            "visibility": "list",
            "supported_in_api": true,
            "priority": 1,
            "support_verbosity": true,
            "truncation_policy": ["mode": "tokens", "limit": 10000],
            "experimental_supported_tools": [] as [String],
            "base_instructions": "You are Codex, a coding agent. Work with the user in their workspace until the task is genuinely handled."
        ]
    }
}

/// Tries each source in order and reports which one supplied the template.
public struct CatalogTemplateResolver: @unchecked Sendable {
    public private(set) var template: [String: Any]
    public private(set) var sourceDescription: String
    public private(set) var attemptedSources: [String]

    public init(
        preferredSlug: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        var sources: [CatalogTemplateSource] = []
        if let cli = CodexCLI.locate(environment: environment, fileManager: fileManager) {
            sources.append(CodexCLICatalogTemplate(cli: cli))
        }
        sources.append(StaticCatalogTemplate())

        var attempts: [String] = []
        for source in sources {
            attempts.append(source.sourceDescription)
            if let entry = try? source.templateEntry(preferredSlug: preferredSlug) {
                self.template = entry
                self.sourceDescription = source.sourceDescription
                self.attemptedSources = attempts
                return
            }
        }
        let fallback = StaticCatalogTemplate()
        self.template = (try? fallback.templateEntry(preferredSlug: preferredSlug)) ?? [:]
        self.sourceDescription = fallback.sourceDescription
        self.attemptedSources = attempts
    }
}

/// A resolved template is itself a valid source, which lets callers resolve once
/// and pass the result to the writer without resolving again.
extension CatalogTemplateResolver: CatalogTemplateSource {
    public func templateEntry(preferredSlug: String) throws -> [String: Any]? { template }
}
