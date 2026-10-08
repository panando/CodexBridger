import Foundation

/// What one config.toml key currently holds.
public enum GlobalSettingState: Equatable, Sendable {
    /// Not present in the file: the product's own default applies.
    case unset
    /// Present in the shape the control writes, so this screen may change it.
    case value(raw: String, parsed: SettingValue)
    /// Present in a shape this screen must not rewrite — a granular approval_policy table, a
    /// number where a choice belongs, a choice value this build does not know. Read, shown,
    /// never overwritten.
    case advancedForm(raw: String)
}

/// A parsed config.toml value, in the shape the matching control needs.
public enum SettingValue: Equatable, Sendable {
    case flag(Bool)
    case choice(String)
    case number(Int)
    case text(String)
    case list([String])
}

/// Reads the catalog's keys out of config.toml text, without modifying anything.
///
/// Only the top-level region is read: `TOMLDocument.topLevelRawValue` stops at the first
/// table header, so a `web_search` that lives inside `[features]` is not mistaken for the
/// top-level setting of the same name.
public enum GlobalSettingsReader {

    /// One entry per key the catalog shows; keys the file does not set come back as `.unset`.
    public static func states(in text: String) -> [String: GlobalSettingState] {
        let document = TOMLDocument(text: text)
        var result: [String: GlobalSettingState] = [:]
        for setting in GlobalSettingsCatalog.settings {
            result[setting.key] = state(of: setting, in: document)
        }
        return result
    }

    private static func state(of setting: GlobalSetting, in document: TOMLDocument) -> GlobalSettingState {
        guard let raw = document.topLevelRawValue(for: setting.key) else { return .unset }
        switch setting.control {
        case .toggle:
            if raw == "true" { return .value(raw: raw, parsed: .flag(true)) }
            if raw == "false" { return .value(raw: raw, parsed: .flag(false)) }
            return .advancedForm(raw: raw)
        case let .choice(allowed):
            // A value outside the documented set is left alone rather than silently replaced:
            // a newer build may accept values this one has never heard of.
            guard let value = decodeString(raw), allowed.contains(value) else {
                return .advancedForm(raw: raw)
            }
            return .value(raw: raw, parsed: .choice(value))
        case .integer:
            guard let number = decodeInteger(raw) else { return .advancedForm(raw: raw) }
            return .value(raw: raw, parsed: .number(number))
        case .text:
            guard let value = decodeString(raw) else { return .advancedForm(raw: raw) }
            return .value(raw: raw, parsed: .text(value))
        case .stringArray:
            guard let list = decodeStringList(raw) else { return .advancedForm(raw: raw) }
            return .value(raw: raw, parsed: .list(list))
        }
    }

    // MARK: - Value shapes

    /// A quoted TOML string, in either quote style. Returns nil for anything else.
    static func decodeString(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { return nil }
        if text.hasPrefix("\"") && text.hasSuffix("\"") {
            return unescapeBasic(String(text.dropFirst().dropLast()))
        }
        if text.hasPrefix("'") && text.hasSuffix("'") {
            return String(text.dropFirst().dropLast())
        }
        return nil
    }

    /// A TOML integer, allowing the digit-separating underscores TOML permits.
    static func decodeInteger(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        var body = text
        var negative = false
        if body.hasPrefix("-") { negative = true; body = String(body.dropFirst()) }
        guard !body.isEmpty else { return nil }
        let digits = CharacterSet(charactersIn: "0123456789_")
        guard body.unicodeScalars.allSatisfy({ digits.contains($0) }) else { return nil }
        let cleaned = body.replacingOccurrences(of: "_", with: "")
        guard let value = Int(cleaned) else { return nil }
        return negative ? -value : value
    }

    /// An array of quoted strings, which may span lines.
    static func decodeStringList(_ raw: String) -> [String]? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("["), text.hasSuffix("]") else { return nil }
        let inner = String(text.dropFirst().dropLast())
        var items: [String] = []
        var buffer = ""
        var quote: Character?
        var escaped = false
        for character in inner {
            if let open = quote {
                if escaped { buffer.append(character); escaped = false; continue }
                if character == "\\" { escaped = true; buffer.append(character); continue }
                if character == open {
                    items.append(open == "\"" ? unescapeBasic(buffer) : buffer)
                    buffer = ""
                    quote = nil
                    continue
                }
                buffer.append(character)
                continue
            }
            if character == "\"" || character == "'" { quote = character; buffer = ""; continue }
            if character == "," || character.isWhitespace { continue }
            // Anything not inside quotes would make this a mixed array, which the control cannot
            // represent faithfully.
            return nil
        }
        guard quote == nil, escaped == false else { return nil }
        return items
    }

    /// Undoes the escape sequences a TOML basic string may carry.
    private static func unescapeBasic(_ text: String) -> String {
        var out = ""
        var escaped = false
        for character in text {
            if escaped {
                switch character {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                default: out.append(character)
                }
                escaped = false
                continue
            }
            if character == "\\" { escaped = true; continue }
            out.append(character)
        }
        if escaped { out.append("\\") }
        return out
    }
}
