import Foundation

/// One key's pending change.
public enum SettingChange: Equatable, Sendable {
    case write(SettingValue)
    case remove
}

/// The pending edits for the settings screen.
///
/// It holds only the difference between the file as loaded and the user's choices, so the
/// writer never has to guess what changed, and a value put back the way the file already had it
/// stops being a change at all.
public struct GlobalSettingsDraft: Equatable, Sendable {
    /// What the file held when the screen opened, keyed by key.
    public let loaded: [String: GlobalSettingState]
    /// Only the keys that actually differ, with what to do about them.
    public private(set) var changes: [String: SettingChange]

    public init(loaded: [String: GlobalSettingState]) {
        self.loaded = loaded
        self.changes = [:]
    }

    public var isDirty: Bool { !changes.isEmpty }

    /// The keys to write, in catalog order so the result is independent of the editing order.
    public var changedKeys: [String] {
        GlobalSettingsCatalog.settings.map(\.key).filter { changes[$0] != nil }
    }

    /// The raw TOML text this key had when the screen opened, for the writer's byte comparison.
    public func loadedRawValue(for key: String) -> String? {
        guard case let .value(raw, _)? = loaded[key] else { return nil }
        return raw
    }

    public mutating func set(_ value: SettingValue, for key: String) {
        guard mayChange(key) else { return }
        // Putting a key back to the value the file already has is not a change.
        if loadedParsedValue(for: key) == value {
            changes.removeValue(forKey: key)
            return
        }
        changes[key] = .write(value)
    }

    public mutating func clear(_ key: String) {
        guard mayChange(key) else { return }
        // Nothing there to remove.
        if loaded[key] == nil || loaded[key] == .unset {
            changes.removeValue(forKey: key)
            return
        }
        changes[key] = .remove
    }

    /// Forgets the pending change for the given keys.
    ///
    /// The conflict prompt's second choice is "drop these keys and write the rest", which needs
    /// exactly this: a chosen subset forgotten, everything else still pending.
    public mutating func discardChanges(for keys: [String]) {
        for key in keys { changes.removeValue(forKey: key) }
    }

    public mutating func reset() { changes = [:] }

    // MARK: - Rules

    /// Whether this screen is allowed to touch the key at all: it must be a key the page draws,
    /// and the file must not hold it in a form this screen cannot represent.
    private func mayChange(_ key: String) -> Bool {
        guard GlobalSettingsCatalog.settings.contains(where: { $0.key == key }) else {
            return false
        }
        if case .advancedForm = loaded[key] { return false }
        return true
    }

    private func loadedParsedValue(for key: String) -> SettingValue? {
        guard case let .value(_, parsed)? = loaded[key] else { return nil }
        return parsed
    }
}
