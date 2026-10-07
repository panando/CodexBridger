import Foundation

/// One model catalog file already present on this machine.
public struct LocalCatalogFile: Identifiable, Equatable, Sendable {
    public var url: URL
    /// Number of models the file declares, when it parses. Nil for a file that does not.
    public var modelCount: Int?
    public var byteCount: Int
    public var modifiedAt: Date?

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL, modelCount: Int?, byteCount: Int, modifiedAt: Date?) {
        self.url = url
        self.modelCount = modelCount
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }
}

/// Lists the catalog files sitting in a Codex home, so the import sheet can offer them.
///
/// A user who already has catalogs on this machine should not have to find them in Finder. Every
/// `.json` in the directory is offered — including files this app did not write and backup copies
/// — because the whole point is to reuse work that already exists. Files that do not parse are
/// still listed, with an unknown model count, so the user can see what is there and get a clear
/// error rather than a file that silently never appears.
public enum ModelCatalogFiles {

    public static func list(
        in directory: URL,
        fileManager: FileManager = .default
    ) -> [LocalCatalogFile] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        var found: [LocalCatalogFile] = []
        for name in names {
            guard name.lowercased().hasSuffix(".json") else { continue }
            let url = directory.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            let modified = attributes?[.modificationDate] as? Date
            found.append(
                LocalCatalogFile(
                    url: url,
                    modelCount: modelCount(in: url, fileManager: fileManager),
                    byteCount: size,
                    modifiedAt: modified
                )
            )
        }
        // Newest first; a file with no timestamp sorts last, and ties fall back to the name so
        // the order never depends on how the directory happened to enumerate.
        return found.sorted { lhs, rhs in
            switch (lhs.modifiedAt, rhs.modifiedAt) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.name < rhs.name
            }
        }
    }

    /// Counts the entries in the file's `models` array, or nil when it does not parse.
    private static func modelCount(in url: URL, fileManager: FileManager) -> Int? {
        guard let data = fileManager.contents(atPath: url.path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [Any] else {
            return nil
        }
        return models.count
    }
}
