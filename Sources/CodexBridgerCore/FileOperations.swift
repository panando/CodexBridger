import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Atomic file writes.
///
/// Every Codex-facing file is written to a sibling temporary file and then
/// renamed over the destination. rename(2) is atomic within a filesystem, so a
/// crash or a kill mid-write can never leave Codex with a half-written
/// config.toml, auth.json or model catalog.
public enum AtomicFile {
    public enum WriteError: Error, LocalizedError {
        case renameFailed(path: String, errno: Int32)

        public var errorDescription: String? {
            switch self {
            case let .renameFailed(path, code):
                return "Atomic rename failed for " + path + " (errno " + String(code) + ")"
            }
        }
    }

    @discardableResult
    public static func write(_ data: Data, to destination: URL, fileManager: FileManager = .default) throws -> URL {
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(
            "." + destination.lastPathComponent + ".tmp-" + UUID().uuidString
        )
        do {
            try data.write(to: temp, options: [])
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
        // Flush to disk before the rename so the rename cannot publish an empty file.
        if let handle = try? FileHandle(forWritingTo: temp) {
            try? handle.synchronize()
            try? handle.close()
        }
        if rename(temp.path, destination.path) != 0 {
            let code = errno
            try? fileManager.removeItem(at: temp)
            if code == EEXIST || code == ENOTEMPTY {
                try? fileManager.removeItem(at: destination)
                if rename(temp.path, destination.path) == 0 { return destination }
            }
            throw WriteError.renameFailed(path: destination.path, errno: code)
        }
        return destination
    }

    @discardableResult
    public static func write(_ string: String, to destination: URL, fileManager: FileManager = .default) throws -> URL {
        try write(Data(string.utf8), to: destination, fileManager: fileManager)
    }
}

/// What kind of file a backup covers. The two kinds differ only in file naming.
public enum BackupKind: String, Sendable {
    case config
    case auth

    var stem: String { rawValue }

    var fileExtension: String {
        switch self {
        case .config: return "toml"
        case .auth: return "json"
        }
    }
}

/// Creates the timestamped backups CodexBridger makes before touching config.toml
/// or auth.json.
///
/// Layout: <codex home>/backup/config-backup/config-<provider>-yyyy-MM-dd-HHmm-bak.toml and
/// auth-<provider>-yyyy-MM-dd-HHmm-bak.json. The provider segment names the provider whose
/// configuration the file holds, so a backup is identifiable without opening it. Because the
/// timestamp only resolves to the minute, a second backup inside the same minute is disambiguated
/// with a numeric suffix (-2, -3, ...) so an earlier backup is never overwritten.
public struct BackupManager {
    public let paths: CodexPaths
    public let fileManager: FileManager

    public init(paths: CodexPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    /// Placeholder used when the file being backed up names no provider at all, e.g. a
    /// hand-written config.toml. Keeps the filename shape identical either way.
    public static let unknownProviderSegment = "unknown"

    /// e.g. config-deepseek-2026-10-05-1930-bak.toml
    ///
    /// The provider segment is sanitised to the identifier character set Codex allows, so a
    /// provider name can never inject a path separator or a newline into the backup filename.
    public static func backupFileName(
        kind: BackupKind,
        provider: String,
        date: Date,
        sequence: Int = 1
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let stamp = formatter.string(from: date)
        let suffix = sequence <= 1 ? "" : "-" + String(sequence)
        let segment = sanitizedProviderSegment(provider)
        return kind.stem + "-" + segment + "-" + stamp + "-bak" + suffix + "." + kind.fileExtension
    }

    /// Reduces a provider id to characters that are safe inside a filename.
    private static func sanitizedProviderSegment(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return unknownProviderSegment }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.isEmpty ? unknownProviderSegment : cleaned
    }

    /// Copies `source` into the backup directory. Returns nil when the source does
    /// not exist yet, which is the normal case on a fresh machine.
    @discardableResult
    public func backup(
        _ source: URL,
        kind: BackupKind,
        provider: String = BackupManager.unknownProviderSegment,
        now: Date = Date()
    ) throws -> URL? {
        guard fileManager.fileExists(atPath: source.path) else { return nil }
        try fileManager.createDirectory(at: paths.backupDirectory, withIntermediateDirectories: true)
        let data = try Data(contentsOf: source)

        var sequence = 1
        var target = paths.backupDirectory.appendingPathComponent(
            BackupManager.backupFileName(kind: kind, provider: provider, date: now, sequence: sequence)
        )
        while fileManager.fileExists(atPath: target.path) {
            sequence += 1
            target = paths.backupDirectory.appendingPathComponent(
                BackupManager.backupFileName(kind: kind, provider: provider, date: now, sequence: sequence)
            )
        }
        try AtomicFile.write(data, to: target, fileManager: fileManager)
        return target
    }
}
