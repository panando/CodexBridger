import Foundation

/// Produces <provider>-model-catalog.json, the file Codex reads to learn which models a
/// provider offers and what they can do.
///
/// This is the only place that file is written. Activation goes through it, and so does
/// saving a provider Codex is currently pointed at, so a catalog produced by activating and
/// one produced by saving can never drift apart.
///
/// Rendering and writing are separate steps on purpose: rendering is pure and testable, and
/// the write can then be skipped when the bytes on disk are already correct.
public struct ModelCatalogWriter: @unchecked Sendable {
    public let paths: CodexPaths
    public let templateSource: CatalogTemplateSource
    public let fileManager: FileManager

    public init(
        paths: CodexPaths,
        templateSource: CatalogTemplateSource,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.templateSource = templateSource
        self.fileManager = fileManager
    }

    /// A catalog that has been generated, serialised and schema-checked, but not written.
    public struct Rendered: Equatable, Sendable {
        public var providerID: String
        public var url: URL
        public var json: String

        public init(providerID: String, url: URL, json: String) {
            self.providerID = providerID
            self.url = url
            self.json = json
        }
    }

    /// What a write did, so callers can tell "rewritten" from "already correct".
    public struct WriteOutcome: Equatable, Sendable {
        public enum Action: String, Equatable, Sendable {
            /// The file on disk was replaced.
            case written
            /// The file on disk already held exactly these bytes, so nothing was touched.
            case unchanged
        }

        public var action: Action
        public var catalog: Rendered

        public init(action: Action, catalog: Rendered) {
            self.action = action
            self.catalog = catalog
        }
    }

    // MARK: - Rendering

    /// Builds the catalog for a provider. Writes nothing.
    public func render(
        provider: ProviderConfiguration,
        preferredTemplateSlug: String
    ) throws -> Rendered {
        let generator = ModelCatalogGenerator(templateSource: templateSource)
        let catalog = try generator.makeCatalog(
            provider: provider,
            preferredTemplateSlug: preferredTemplateSlug
        )
        let json = try ModelCatalogGenerator.serialize(catalog)
        try ModelCatalogWriter.validateSchema(json)
        return Rendered(
            providerID: provider.id,
            url: paths.catalog(for: provider.id),
            json: json
        )
    }

    // MARK: - Writing

    /// Writes a rendered catalog, replacing whatever is there.
    ///
    /// Activation uses this: activating is an explicit "write everything" action, so it does
    /// not consult what is already on disk.
    @discardableResult
    public func write(_ rendered: Rendered) throws -> URL {
        try AtomicFile.write(rendered.json, to: rendered.url, fileManager: fileManager)
        return rendered.url
    }

    /// Renders and writes, but only when the file on disk does not already hold these bytes.
    ///
    /// Saving a provider runs on every edit, so an unconditional write would bump the file's
    /// modification date for changes that never reached the catalog, which makes it impossible
    /// to tell from the timestamp whether anything was actually regenerated.
    @discardableResult
    public func writeIfChanged(
        provider: ProviderConfiguration,
        preferredTemplateSlug: String
    ) throws -> WriteOutcome {
        let rendered = try render(
            provider: provider,
            preferredTemplateSlug: preferredTemplateSlug
        )
        if fileManager.contents(atPath: rendered.url.path) == Data(rendered.json.utf8) {
            return WriteOutcome(action: .unchanged, catalog: rendered)
        }
        try write(rendered)
        return WriteOutcome(action: .written, catalog: rendered)
    }

    // MARK: - Schema guard

    /// Guards the invariants Codex enforces on a catalog before the file is allowed near
    /// ~/.codex: a non-empty model list, and instructions on every entry.
    public static func validateSchema(_ json: String) throws {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else {
            throw ModelCatalogGenerator.GenerationError.noUsableTemplate
        }
        guard !models.isEmpty else {
            throw ModelCatalogGenerator.GenerationError.noUsableTemplate
        }
        for entry in models {
            let hasInstructions = (entry["base_instructions"] as? String)?.isEmpty == false
            let messages = entry["model_messages"] as? [String: Any]
            let hasTemplate = (messages?["instructions_template"] as? String)?.isEmpty == false
            guard hasInstructions || hasTemplate else {
                throw ModelCatalogGenerator.GenerationError.templateMissingInstructions
            }
        }
    }
}
