import Foundation

/// Persists CodexBridger own state under <codex home>/codexbridger/config.json.
///
/// The location is deliberate: it lives beside the Codex files it manages, so a
/// CODEX_HOME override keeps the app state and the Codex config in step, and a
/// user can back up or move one folder.
public final class ConfigurationStore: @unchecked Sendable {
    public let paths: CodexPaths
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(paths: CodexPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public var configurationExists: Bool {
        fileManager.fileExists(atPath: paths.appConfiguration.path)
    }

    public enum StoreError: Error, LocalizedError {
        case decodingFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .decodingFailed(message):
                return "无法解析已保存的 CodexBridger 配置: " + message
            }
        }
    }

    /// Loads the saved configuration, or an empty one on a fresh install.
    public func load() throws -> CodexBridgerConfiguration {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: paths.appConfiguration.path) else {
            return CodexBridgerConfiguration()
        }
        let data = try Data(contentsOf: paths.appConfiguration)
        if data.isEmpty { return CodexBridgerConfiguration() }
        do {
            let decoder = JSONDecoder()
            let configuration = try decoder.decode(CodexBridgerConfiguration.self, from: data)
            return configuration
        } catch {
            // Never silently discard user data; surface it so the UI can warn.
            throw StoreError.decodingFailed(error.localizedDescription)
        }
    }

    public func save(_ configuration: CodexBridgerConfiguration) throws {
        lock.lock()
        defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(configuration)
        data.append(Data(TOMLDocument.newline.utf8))
        try AtomicFile.write(data, to: paths.appConfiguration, fileManager: fileManager)
    }
}
