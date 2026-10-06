import Foundation

/// A deliberately small, surgical TOML editor.
///
/// config.toml is shared with Codex itself and with plugin/MCP configuration, so
/// CodexBridger never re-serialises the whole file. It splices only the specific
/// top-level keys it owns and the single [model_providers.<id>] block it manages.
/// Everything else is preserved byte for byte, which is what keeps a user file
/// full of unrelated sections safe.
public struct TOMLDocument {
    private var lines: [String]

    /// Shared newline constant so no source file needs a literal escape.
    public static let newline = String(UnicodeScalar(10))
    private static let dquote = Character(UnicodeScalar(34))
    private static let squote = Character(UnicodeScalar(39))
    private static let backslash = Character(UnicodeScalar(92))

    public init(text: String = "") {
        self.lines = text.isEmpty ? [] : text.components(separatedBy: TOMLDocument.newline)
    }

    /// The current document text. Joining restores the original text exactly,
    /// including a trailing newline, because an empty final line round-trips.
    public var text: String { lines.joined(separator: TOMLDocument.newline) }

    // MARK: - Layout scanning

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
    }

    /// Index of the first table header, i.e. where the top-level region ends.
    private var firstHeaderIndex: Int {
        lines.firstIndex { TOMLDocument.headerPath($0) != nil } ?? lines.count
    }

    /// Parses "[a.b]" / "[[a.b]]" into its key path, or nil if the line is not a
    /// table header. Quoted segments are unquoted.
    static func headerPath(_ line: String) -> [String]? {
        let chars = Array(line)
        var inBasic = false
        var inLiteral = false
        var escaped = false
        var depth = 0
        var start = -1
        var end = -1
        for (index, c) in chars.enumerated() {
            if inBasic {
                if escaped { escaped = false }
                else if c == TOMLDocument.backslash { escaped = true }
                else if c == TOMLDocument.dquote { inBasic = false }
                continue
            }
            if inLiteral {
                if c == TOMLDocument.squote { inLiteral = false }
                continue
            }
            if c == TOMLDocument.dquote { inBasic = true; continue }
            if c == TOMLDocument.squote { inLiteral = true; continue }
            if c == "[" {
                depth += 1
                if start < 0 { start = index }
            } else if c == "]" {
                depth -= 1
                if depth == 0 { end = index; break }
            } else if depth == 0 && !TOMLDocument.trimmed(String(c)).isEmpty {
                return nil
            }
        }
        guard start >= 0, end > start else { return nil }
        var inner = String(chars[(start + 1)..<end])
        // Array-of-tables: strip the second bracket pair.
        if inner.hasPrefix("[") && inner.hasSuffix("]") {
            inner = String(inner.dropFirst().dropLast())
        }
        return parsePath(inner)
    }

    static func parsePath(_ raw: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var inBasic = false
        var inLiteral = false
        var escaped = false
        for c in raw {
            if inBasic {
                current.append(c)
                if escaped { escaped = false }
                else if c == TOMLDocument.backslash { escaped = true }
                else if c == TOMLDocument.dquote { inBasic = false }
                continue
            }
            if inLiteral {
                current.append(c)
                if c == TOMLDocument.squote { inLiteral = false }
                continue
            }
            if c == TOMLDocument.dquote { inBasic = true; current.append(c); continue }
            if c == TOMLDocument.squote { inLiteral = true; current.append(c); continue }
            if c == "." {
                segments.append(unquote(current.trimmingCharacters(in: .whitespaces)))
                current = ""
            } else {
                current.append(c)
            }
        }
        let tail = unquote(current.trimmingCharacters(in: .whitespaces))
        if !tail.isEmpty || segments.isEmpty { segments.append(tail) }
        return segments.filter { !$0.isEmpty }
    }

    private static func unquote(_ raw: String) -> String {
        guard raw.count >= 2 else { return raw }
        if (raw.hasPrefix(String(dquote)) && raw.hasSuffix(String(dquote))) ||
           (raw.hasPrefix(String(squote)) && raw.hasSuffix(String(squote))) {
            return String(raw.dropFirst().dropLast())
        }
        return raw
    }

    /// Splits "key = value" into its key and the raw value text on that line.
    private static func splitKeyAndValue(_ line: String) -> (key: String, value: String)? {
        let chars = Array(line)
        var inBasic = false
        var inLiteral = false
        var escaped = false
        for (index, c) in chars.enumerated() {
            if inBasic {
                if escaped { escaped = false }
                else if c == TOMLDocument.backslash { escaped = true }
                else if c == TOMLDocument.dquote { inBasic = false }
                continue
            }
            if inLiteral {
                if c == TOMLDocument.squote { inLiteral = false }
                continue
            }
            if c == TOMLDocument.dquote { inBasic = true; continue }
            if c == TOMLDocument.squote { inLiteral = true; continue }
            if c == "=" {
                let key = unquote(String(chars[0..<index]).trimmingCharacters(in: .whitespaces))
                let value = String(chars[(index + 1)...]).trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { return nil }
                return (key, value)
            }
        }
        return nil
    }

    /// Index of the last physical line belonging to the statement at `start`.
    /// Arrays and inline tables may wrap, so bracket depth decides the extent.
    private func valueEndIndex(from start: Int) -> Int {
        var depth = 0
        var inBasic = false
        var inLiteral = false
        var escaped = false
        var sawEquals = false
        var index = start
        while index < lines.count {
            for c in lines[index] {
                if inBasic {
                    if escaped { escaped = false }
                    else if c == TOMLDocument.backslash { escaped = true }
                    else if c == TOMLDocument.dquote { inBasic = false }
                    continue
                }
                if inLiteral {
                    if c == TOMLDocument.squote { inLiteral = false }
                    continue
                }
                if c == TOMLDocument.dquote { inBasic = true; continue }
                if c == TOMLDocument.squote { inLiteral = true; continue }
                if c == "=" { sawEquals = true; continue }
                if !sawEquals { continue }
                if c == "[" || c == "{" { depth += 1 }
                else if c == "]" || c == "}" { depth -= 1 }
            }
            if depth <= 0 { return index }
            index += 1
        }
        return max(start, lines.count - 1)
    }

    // MARK: - Top-level keys

    public func hasTopLevelKey(_ key: String) -> Bool {
        topLevelRawValue(for: key) != nil
    }

    /// Raw TOML text of a top-level value, e.g. a quoted string or array literal.
    public func topLevelRawValue(for key: String) -> String? {
        let end = firstHeaderIndex
        var index = 0
        while index < end {
            if let kv = TOMLDocument.splitKeyAndValue(lines[index]), kv.key == key {
                let last = valueEndIndex(from: index)
                var parts: [String] = [kv.value]
                if last > index, index + 1 <= last {
                    parts.append(contentsOf: lines[(index + 1)...last])
                }
                return parts.joined(separator: TOMLDocument.newline)
                    .trimmingCharacters(in: .whitespaces)
            }
            index += 1
        }
        return nil
    }

    /// Decoded value of a top-level string key, e.g. model = "gpt-5.5".
    /// Decoded value of a top-level key. Quoted values are unquoted; anything else
    /// (numbers, booleans, arrays) is returned as written.
    public func topLevelString(_ key: String) -> String? {
        guard let raw = topLevelRawValue(for: key) else { return nil }
        let t = raw.trimmingCharacters(in: .whitespaces)
        let dq = String(TOMLDocument.dquote)
        let sq = String(TOMLDocument.squote)
        if t.count >= 2 && t.hasPrefix(dq) && t.hasSuffix(dq) {
            return TOMLDocument.unquote(t)
        }
        if t.count >= 2 && t.hasPrefix(sq) && t.hasSuffix(sq) {
            return TOMLDocument.unquote(t)
        }
        return t
    }

    public mutating func setTopLevel(key: String, rawValue: String) {
        let end = firstHeaderIndex
        var index = 0
        while index < end {
            if let kv = TOMLDocument.splitKeyAndValue(lines[index]), kv.key == key {
                let last = valueEndIndex(from: index)
                lines.replaceSubrange(index...last, with: [key + " = " + rawValue])
                return
            }
            index += 1
        }
        var insertAt = end
        while insertAt > 0 && TOMLDocument.trimmed(lines[insertAt - 1]).isEmpty {
            insertAt -= 1
        }
        lines.insert(key + " = " + rawValue, at: insertAt)
    }

    public mutating func removeTopLevel(key: String) {
        let end = firstHeaderIndex
        var index = 0
        while index < end {
            if let kv = TOMLDocument.splitKeyAndValue(lines[index]), kv.key == key {
                let last = valueEndIndex(from: index)
                lines.removeSubrange(index...last)
                return
            }
            index += 1
        }
    }

    // MARK: - Table regions

    private static func isDescendant(_ ancestor: [String], of path: [String]) -> Bool {
        path.count > ancestor.count && Array(path.prefix(ancestor.count)) == ancestor
    }

    /// The line range of a table and all of its sub-tables.
    public func tableRegion(_ path: [String]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: { TOMLDocument.headerPath($0) == path }) else {
            return nil
        }
        var end = start + 1
        while end < lines.count {
            if let header = TOMLDocument.headerPath(lines[end]) {
                let isSub = TOMLDocument.isDescendant(path, of: header)
                if !isSub { break }
            }
            end += 1
        }
        // Leave the blank separator line after the block outside the region, so
        // replacing a block is byte-identical whether it was appended or replaced.
        while end - 1 > start && TOMLDocument.trimmed(lines[end - 1]).isEmpty {
            end -= 1
        }
        return start..<end
    }

    public func hasTable(_ path: [String]) -> Bool { tableRegion(path) != nil }

    /// Every table header path in document order. Used to report which providers
    /// a config.toml already defines.
    public func tablePaths() -> [[String]] {
        lines.compactMap { TOMLDocument.headerPath($0) }
    }

    /// Replaces a table (and its sub-tables) with the given canonical lines.
    public mutating func replaceTableRegion(rootPath: [String], rendered: [String]) {
        if let range = tableRegion(rootPath) {
            lines.replaceSubrange(range, with: rendered)
            return
        }
        // Append: keep exactly one blank line between blocks.
        while let last = lines.last, TOMLDocument.trimmed(last).isEmpty { lines.removeLast() }
        if !lines.isEmpty { lines.append("") }
        lines.append(contentsOf: rendered)
        lines.append("")
    }

    public mutating func removeTableRegion(rootPath: [String]) {
        guard let range = tableRegion(rootPath) else { return }
        lines.removeSubrange(range)
        // Collapse a blank line left directly before a following header.
        if range.lowerBound < lines.count, TOMLDocument.trimmed(lines[range.lowerBound]).isEmpty {
            var next = range.lowerBound + 1
            while next < lines.count && TOMLDocument.trimmed(lines[next]).isEmpty { next += 1 }
            if next < lines.count, TOMLDocument.headerPath(lines[next]) != nil {
                lines.remove(at: range.lowerBound)
            }
        }
    }
}

/// Renders TOML scalars, arrays and inline tables.
public enum TOMLValueWriter {
    private static let dquote = Character(UnicodeScalar(34))
    private static let backslash = Character(UnicodeScalar(92))

    /// Escapes a string as a TOML basic string, always quoted.
    public static func string(_ value: String) -> String {
        var out = String(dquote)
        for scalar in value.unicodeScalars {
            switch scalar {
            case UnicodeScalar(34):
                out.append(backslash); out.append(dquote)
            case UnicodeScalar(92):
                out.append(backslash); out.append(backslash)
            case UnicodeScalar(8):
                out.append(backslash); out.append("b")
            case UnicodeScalar(9):
                out.append(backslash); out.append("t")
            case UnicodeScalar(10):
                out.append(backslash); out.append("n")
            case UnicodeScalar(12):
                out.append(backslash); out.append("f")
            case UnicodeScalar(13):
                out.append(backslash); out.append("r")
            default:
                if scalar.value < 0x20 {
                    out.append(backslash)
                    out.append("u" + String(format: "%04X", scalar.value))
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out.append(dquote)
        return out
    }

    public static func bool(_ value: Bool) -> String { value ? "true" : "false" }

    public static func int(_ value: Int) -> String { String(value) }

    public static func stringArray(_ values: [String]) -> String {
        "[" + values.map { string($0) }.joined(separator: ", ") + "]"
    }

    /// Renders a TOML inline table, quoting keys that are not bare keys.
    public static func inlineTable(_ pairs: [(String, String)]) -> String {
        let body = pairs
            .sorted { $0.0 < $1.0 }
            .map { key, value in keyString(key) + " = " + string(value) }
            .joined(separator: ", ")
        return "{ " + body + " }"
    }

    public static func keyString(_ key: String) -> String {
        let bare = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        let isBare = !key.isEmpty && key.unicodeScalars.allSatisfy { bare.contains($0) }
        return isBare ? key : string(key)
    }
}
