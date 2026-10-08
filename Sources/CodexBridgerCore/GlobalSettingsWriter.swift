import Foundation

/// A key that changed on disk after this screen loaded it.
public struct GlobalSettingsConflict: Equatable, Sendable {
    public let key: String
    /// The raw text as it was when the screen opened. Nil when the key was absent.
    public let loadedRaw: String?
    /// The raw text on disk right now. Nil when the key has since been removed.
    public let currentRaw: String?

    public init(key: String, loadedRaw: String?, currentRaw: String?) {
        self.key = key
        self.loadedRaw = loadedRaw
        self.currentRaw = currentRaw
    }
}

public enum GlobalSettingsWriteError: Error, LocalizedError, Equatable {
    case conflictingKeys([GlobalSettingsConflict])
    /// The file was written, then read back, and did not hold what we meant to write.
    case verificationFailed(key: String, expected: String?, found: String?)

    public var errorDescription: String? {
        switch self {
        case let .conflictingKeys(conflicts):
            return "这些键刚被别的程序改了：" + conflicts.map(\.key).joined(separator: ", ")
        case let .verificationFailed(key, expected, found):
            return "写完之后回读，" + key + " 的值不是我们写的那个（期望 "
                + (expected ?? "（已删除）") + "，实际 " + (found ?? "（不存在）") + "）。"
        }
    }
}

public struct GlobalSettingsWriteResult: Equatable, Sendable {
    public var configURL: URL
    public var backupURL: URL?
    public var writtenKeys: [String]
    public var configTOML: String
    public var warnings: [String]

    public init(
        configURL: URL,
        backupURL: URL? = nil,
        writtenKeys: [String] = [],
        configTOML: String = "",
        warnings: [String] = []
    ) {
        self.configURL = configURL
        self.backupURL = backupURL
        self.writtenKeys = writtenKeys
        self.configTOML = configTOML
        self.warnings = warnings
    }
}

/// The only thing allowed to change a non-provider key in config.toml.
///
/// Order of operations mirrors the activation writer: nothing is written until the file has
/// been read again, a backup is taken before the first byte changes, and the key set can only
/// come from the catalog — there is no entry point that takes an arbitrary key name.
public struct GlobalSettingsWriter: @unchecked Sendable {
    public let paths: CodexPaths
    public let fileManager: FileManager
    public let now: () -> Date

    /// The segment in the backup filename. It says what the backup is about, so a global
    /// settings backup is never mistaken for a provider's.
    public static let backupSegment = "settings"

    /// How the text reaches the disk. Injectable so the read-back check below can be shown to
    /// catch a write that silently does not land, which is otherwise unreachable from a test.
    public typealias FileWriter = (String, URL, FileManager) throws -> Void
    private let writeFile: FileWriter

    public init(
        paths: CodexPaths,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        writeFile: @escaping FileWriter = { text, url, fileManager in
            try AtomicFile.write(text, to: url, fileManager: fileManager)
        }
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.now = now
        self.writeFile = writeFile
    }

    /// The keys the user changed that somebody else changed too, since the screen loaded them.
    ///
    /// Comparison is on the raw text, deliberately: a value rewritten in the other quote style,
    /// or reflowed, still counts as a change, because this writer promises not to overwrite bytes
    /// it did not see the user choose.
    public func conflicts(for draft: GlobalSettingsDraft) -> [GlobalSettingsConflict] {
        guard let current = currentText() else { return [] }
        let document = TOMLDocument(text: current)
        return draft.changedKeys.compactMap { key in
            let currentRaw = document.topLevelRawValue(for: key)
            let loadedRaw = draft.loadedRawValue(for: key)
            guard currentRaw != loadedRaw else { return nil }
            return GlobalSettingsConflict(key: key, loadedRaw: loadedRaw, currentRaw: currentRaw)
        }
    }

    @discardableResult
    public func write(
        _ draft: GlobalSettingsDraft,
        acceptingConflicts: Bool = false
    ) throws -> GlobalSettingsWriteResult {
        let existing = currentText()
        guard draft.isDirty else {
            return GlobalSettingsWriteResult(configURL: paths.configTOML, configTOML: existing ?? "")
        }

        let conflicts = conflicts(for: draft)
        if !conflicts.isEmpty, !acceptingConflicts {
            // Nothing has been written and nothing has been backed up at this point.
            throw GlobalSettingsWriteError.conflictingKeys(conflicts)
        }

        var document = TOMLDocument(text: existing ?? "")
        for key in draft.changedKeys {
            switch draft.changes[key] {
            case let .write(value):
                document.setTopLevel(key: key, rawValue: Self.render(value))
            case .remove:
                document.removeTopLevel(key: key)
            case nil:
                continue
            }
        }
        let text = document.text

        var backupURL: URL?
        var warnings: [String] = []
        if existing != nil {
            backupURL = try BackupManager(paths: paths, fileManager: fileManager)
                .backup(
                    paths.configTOML,
                    kind: .config,
                    provider: Self.backupSegment,
                    now: now()
                )
        } else {
            warnings.append("原来没有 config.toml，本次是新建，没有可备份的原文件。")
        }

        try writeFile(text, paths.configTOML, fileManager)

        // Read the file back: a write that quietly did not land must be reported as a failure,
        // never as success. The bytes are known, so this is a cheap, exact check.
        try verify(expectedText: text, for: draft)

        return GlobalSettingsWriteResult(
            configURL: paths.configTOML,
            backupURL: backupURL,
            writtenKeys: draft.changedKeys,
            configTOML: text,
            warnings: warnings
        )
    }

    /// Confirms each intended change is actually in the file now.
    private func verify(expectedText: String, for draft: GlobalSettingsDraft) throws {
        guard let written = try? String(contentsOf: paths.configTOML, encoding: .utf8) else {
            throw GlobalSettingsWriteError.verificationFailed(
                key: draft.changedKeys.first ?? "", expected: expectedText, found: nil
            )
        }
        let document = TOMLDocument(text: written)
        for key in draft.changedKeys {
            switch draft.changes[key] {
            case let .write(value):
                let expected = Self.render(value)
                let found = document.topLevelRawValue(for: key)
                guard found == expected else {
                    throw GlobalSettingsWriteError.verificationFailed(
                        key: key, expected: expected, found: found
                    )
                }
            case .remove:
                guard document.topLevelRawValue(for: key) == nil else {
                    throw GlobalSettingsWriteError.verificationFailed(
                        key: key, expected: nil, found: document.topLevelRawValue(for: key)
                    )
                }
            case nil:
                continue
            }
        }
    }

    private func currentText() -> String? {
        guard fileManager.fileExists(atPath: paths.configTOML.path) else { return nil }
        return try? String(contentsOf: paths.configTOML, encoding: .utf8)
    }

    /// The TOML text a chosen value is written as. Anything not produced here cannot reach the
    /// file, so an unrepresentable value has no way in.
    static func render(_ value: SettingValue) -> String {
        switch value {
        case let .flag(flag): return TOMLValueWriter.bool(flag)
        case let .choice(choice): return TOMLValueWriter.string(choice)
        case let .number(number): return TOMLValueWriter.int(number)
        case let .text(text): return TOMLValueWriter.string(text)
        case let .list(items): return TOMLValueWriter.stringArray(items)
        }
    }
}
