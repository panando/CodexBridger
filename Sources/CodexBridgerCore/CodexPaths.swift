import Foundation

/// Resolves every path CodexBridger writes to.
///
/// Codex relocates its home directory when the CODEX_HOME environment variable is
/// set, so honoring it is both correct for users who set it and the mechanism the
/// test suite uses to run against a throwaway directory instead of the real
/// ~/.codex.
public struct CodexPaths: Equatable, Sendable {
    /// The Codex home directory, normally ~/.codex.
    public let codexHome: URL

    public init(codexHome: URL) {
        self.codexHome = codexHome
    }

    /// Builds paths from the process environment, honoring CODEX_HOME.
    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        if let raw = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            self.codexHome = URL(fileURLWithPath: expanded, isDirectory: true)
        } else {
            let home = fileManager.homeDirectoryForCurrentUser
            self.codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        }
    }

    /// <codex home>/config.toml
    public var configTOML: URL { codexHome.appendingPathComponent("config.toml") }

    /// <codex home>/auth.json
    public var authJSON: URL { codexHome.appendingPathComponent("auth.json") }

    /// <codex home>/model-catalogs
    public var modelCatalogsDirectory: URL {
        codexHome.appendingPathComponent("model-catalogs", isDirectory: true)
    }

    /// <codex home>/backup/config-backup
    public var backupDirectory: URL {
        codexHome
            .appendingPathComponent("backup", isDirectory: true)
            .appendingPathComponent("config-backup", isDirectory: true)
    }

    /// <codex home>/codexbridger - CodexBridger own persistence folder.
    public var appDirectory: URL {
        codexHome.appendingPathComponent("codexbridger", isDirectory: true)
    }

    /// <codex home>/codexbridger/config.json
    public var appConfiguration: URL {
        appDirectory.appendingPathComponent("config.json")
    }

    /// <codex home>/model-catalogs/<provider>-model-catalog.json
    public func catalog(for providerID: String) -> URL {
        modelCatalogsDirectory.appendingPathComponent("\(providerID)-model-catalog.json")
    }
}
