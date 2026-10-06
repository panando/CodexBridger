import Foundation

/// A read-only view of what ~/.codex currently contains.
public struct CodexConfigSnapshot: Equatable, Sendable {
    public var configExists: Bool
    public var modelProviderID: String?
    public var modelSlug: String?
    public var modelCatalogJSON: String?
    public var modelReasoningEffort: String?
    public var modelReasoningSummary: String?
    public var modelVerbosity: String?
    /// Provider ids already defined under [model_providers.*].
    public var providerIDs: [String]
    /// Whether the catalog file referenced by config.toml actually exists.
    public var catalogFileExists: Bool

    public init(
        configExists: Bool = false,
        modelProviderID: String? = nil,
        modelSlug: String? = nil,
        modelCatalogJSON: String? = nil,
        modelReasoningEffort: String? = nil,
        modelReasoningSummary: String? = nil,
        modelVerbosity: String? = nil,
        providerIDs: [String] = [],
        catalogFileExists: Bool = false
    ) {
        self.configExists = configExists
        self.modelProviderID = modelProviderID
        self.modelSlug = modelSlug
        self.modelCatalogJSON = modelCatalogJSON
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelVerbosity = modelVerbosity
        self.providerIDs = providerIDs
        self.catalogFileExists = catalogFileExists
    }
}

/// Reads config.toml and auth.json without modifying them.
public struct CodexConfigReader {
    public let paths: CodexPaths
    private let fileManager: FileManager

    public init(paths: CodexPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func snapshot() -> CodexConfigSnapshot {
        guard fileManager.fileExists(atPath: paths.configTOML.path),
              let text = try? String(contentsOf: paths.configTOML, encoding: .utf8) else {
            return CodexConfigSnapshot()
        }
        let document = TOMLDocument(text: text)
        let catalogPath = document.topLevelString("model_catalog_json")
        let providerIDs = document.tablePaths()
            .filter { $0.count == 2 && $0[0] == "model_providers" }
            .map { $0[1] }
        return CodexConfigSnapshot(
            configExists: true,
            modelProviderID: document.topLevelString("model_provider"),
            modelSlug: document.topLevelString("model"),
            modelCatalogJSON: catalogPath,
            modelReasoningEffort: document.topLevelString("model_reasoning_effort"),
            modelReasoningSummary: document.topLevelString("model_reasoning_summary"),
            modelVerbosity: document.topLevelString("model_verbosity"),
            providerIDs: providerIDs,
            catalogFileExists: catalogPath.map { fileManager.fileExists(atPath: $0) } ?? false
        )
    }

    /// Names of the keys present in auth.json. Values are deliberately never
    /// surfaced, so credentials cannot leak into logs or screenshots.
    public func authKeyNames() -> [String] {
        guard let data = try? Data(contentsOf: paths.authJSON),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return object.keys.sorted()
    }
}
