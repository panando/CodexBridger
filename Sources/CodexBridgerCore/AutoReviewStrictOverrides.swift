import Foundation

/// Per-model override for `response_format.json_schema.strict`.
///
/// Codex's harness does not send a constant: it observed
/// `glm-5.3-flash` being sent `strict=false`, and the upstream rejecting
/// `strict=true` for it ("response_format.json_schema.strict=false is not
/// supported; omit strict or set it to true"). Probing that model with a
/// constant `strict=true` therefore reports a reviewer that works in
/// production as broken. This table carries the observed values; a slug with no
/// entry is probed with `strict=true`, the canonical setting.
public struct AutoReviewStrictOverrides: Sendable, Equatable, Codable {

    /// slug -> strict. Absent means true.
    public var entries: [String: Bool]

    public init(entries: [String: Bool] = ["glm-5.3-flash": false]) {
        self.entries = entries
    }

    /// The observed defaults from the reference probe's own table.
    public static let `default` = AutoReviewStrictOverrides()

    /// Parses the reference probe's env format: space-separated `<slug>=<true|false>`.
    /// Malformed entries are dropped rather than failing the whole table, and only
    /// `false` disables strict — anything else is read as true.
    public init(parsing text: String) {
        var parsed: [String: Bool] = [:]
        for entry in text.split(separator: " ") {
            let pair = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let slug = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty else { continue }
            // Only an explicit false disables strict; true is the default and
            // storing it would be noise.
            if pair[1].trimmingCharacters(in: .whitespacesAndNewlines) == "false" {
                parsed[slug] = false
            }
        }
        self.entries = parsed
    }

    public func value(for slug: String) -> Bool {
        entries[slug] ?? true
    }

    public mutating func set(_ strict: Bool, for slug: String) {
        if strict {
            // The default is true, so storing it would be noise.
            entries.removeValue(forKey: slug)
        } else {
            entries[slug] = false
        }
    }

    public mutating func remove(_ slug: String) {
        entries.removeValue(forKey: slug)
    }
}
