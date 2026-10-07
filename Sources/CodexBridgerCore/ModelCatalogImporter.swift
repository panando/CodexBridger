import Foundation

/// Reads an existing model catalog file back into model configurations.
///
/// A catalog that Codex or another tool produced carries everything CodexBridger needs to fill
/// the model form: the id, the display name, the context windows, the reasoning levels, the
/// visibility and the ordering. Importing one is how a user avoids retyping a list of models.
///
/// Only those nine values are read. The thirty-odd other fields a real catalog carries — the
/// instructions, the message templates, the tool and modality declarations — are deliberately
/// ignored. CodexBridger re-derives every one of them from a verified template when it generates
/// a catalog, so importing them would mean storing values this project has no evidence for.
///
/// That restriction is enforced by a test: this file must not name any of those fields.
///
/// The parser is pure — it takes bytes and returns values. It never touches the disk.
public enum ModelCatalogImporter {

    /// A model that was read successfully, plus anything that had to be substituted.
    public struct ImportedModel: Equatable, Sendable {
        public var model: ModelConfiguration
        /// Human-readable notes about values that were missing or unusable and were replaced.
        public var notes: [String]

        public init(model: ModelConfiguration, notes: [String] = []) {
            self.model = model
            self.notes = notes
        }
    }

    /// A model that could not be imported at all.
    public struct SkippedModel: Equatable, Sendable {
        public var slug: String?
        public var reason: String

        public init(slug: String?, reason: String) {
            self.slug = slug
            self.reason = reason
        }
    }

    /// Everything a file produced: what came in, what was left out, and what was adjusted.
    public struct ImportOutcome: Equatable, Sendable {
        public var models: [ImportedModel]
        public var skipped: [SkippedModel]
        /// File-level notes, e.g. how many models the file held.
        public var notes: [String]
        /// How many entries the file contained, before any were skipped.
        public var sourceModelCount: Int

        public init(
            models: [ImportedModel],
            skipped: [SkippedModel],
            notes: [String],
            sourceModelCount: Int
        ) {
            self.models = models
            self.skipped = skipped
            self.notes = notes
            self.sourceModelCount = sourceModelCount
        }

        public static let empty = ImportOutcome(
            models: [], skipped: [], notes: [], sourceModelCount: 0
        )
    }

    /// Problems with the file as a whole.
    public enum ImportError: Error, LocalizedError, Equatable {
        case notValidJSON
        /// Valid JSON, but not the {"models": [ … ]} shape Codex requires.
        case unexpectedShape
        case noModels
        /// Every entry was unusable; the reasons are carried so the UI can explain why.
        case nothingImportable([SkippedModel])

        public var errorDescription: String? {
            switch self {
            case .notValidJSON:
                return "这个文件不是合法的 JSON"
            case .unexpectedShape:
                return "这个文件的结构不对，应该是 {\"models\": [ … ]}"
            case .noModels:
                return "这个文件里没有任何模型"
            case let .nothingImportable(skipped):
                let reasons = skipped.map { entry in
                    (entry.slug ?? "（无 slug）") + "：" + entry.reason
                }.joined(separator: "；")
                return "这个文件里的模型没有一个能导入。" + reasons
            }
        }
    }

    /// Fallback used when a file gives no usable context window.
    public static let fallbackContextWindow = ModelCatalogGenerator.defaultContextWindow

    // MARK: - Parsing

    public static func parse(data: Data) throws -> ImportOutcome {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ImportError.notValidJSON
        }
        guard let object = root as? [String: Any],
              let entries = object["models"] as? [[String: Any]] else {
            throw ImportError.unexpectedShape
        }
        guard !entries.isEmpty else { throw ImportError.noModels }

        var imported: [ImportedModel] = []
        var skipped: [SkippedModel] = []
        var seenSlugs = Set<String>()

        for entry in entries {
            let rawSlug = (entry["slug"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let slug = rawSlug, !slug.isEmpty else {
                skipped.append(SkippedModel(slug: nil, reason: "缺少模型 ID（slug）"))
                continue
            }
            guard seenSlugs.insert(slug).inserted else {
                skipped.append(SkippedModel(slug: slug, reason: "同一个文件里有重复的模型 ID"))
                continue
            }
            imported.append(makeModel(slug: slug, entry: entry, priority: imported.count + 1))
        }

        guard !imported.isEmpty else {
            throw ImportError.nothingImportable(skipped)
        }

        var fileNotes: [String] = []
        if !skipped.isEmpty {
            fileNotes.append("文件里共 " + String(entries.count) + " 个模型，"
                             + String(skipped.count) + " 个被跳过。")
        }
        return ImportOutcome(
            models: imported,
            skipped: skipped,
            notes: fileNotes,
            sourceModelCount: entries.count
        )
    }

    // MARK: - One entry

    private static func makeModel(
        slug: String,
        entry: [String: Any],
        priority: Int
    ) -> ImportedModel {
        var notes: [String] = []

        var displayName = text(entry["display_name"])
        if displayName.isEmpty {
            displayName = slug
            notes.append("没有 display_name，用模型 ID 代替")
        }

        var description = text(entry["description"])
        if description.isEmpty {
            description = displayName
            notes.append("没有 description，用显示名称代替")
        }

        var contextWindow = int(entry["context_window"]) ?? 0
        if contextWindow <= 0 {
            contextWindow = fallbackContextWindow
            notes.append("没有可用的 context_window，用 "
                         + String(fallbackContextWindow) + " 代替")
        } else if contextWindow < ProviderDraft.minimumContextWindow {
            notes.append("context_window 小于 "
                         + String(ProviderDraft.minimumContextWindow) + "，已抬到下限")
            contextWindow = ProviderDraft.minimumContextWindow
        }

        var maxContextWindow = int(entry["max_context_window"]) ?? contextWindow
        if maxContextWindow < contextWindow {
            maxContextWindow = contextWindow
            notes.append("max_context_window 小于 context_window，已抬平")
        }

        let rawLevels = (entry["supported_reasoning_levels"] as? [[String: Any]]) ?? []
        let rawEfforts = rawLevels.compactMap { text($0["effort"]) }.filter { !$0.isEmpty }
        var efforts = rawEfforts.compactMap { effort(named: $0) }
        let rejected = rawEfforts.filter { effort(named: $0) == nil }
        if !rejected.isEmpty {
            notes.append("忽略了不支持的推理档位：" + rejected.joined(separator: "、"))
        }
        if efforts.isEmpty {
            efforts = [.medium]
            notes.append("没有可用的推理档位，只用 medium")
        } else {
            // Canonical order, and a level repeated in the file counts once.
            efforts = ReasoningEffort.all.filter { efforts.contains($0) }
        }

        let declaredDefault = text(entry["default_reasoning_level"]).isEmpty
            ? nil
            : effort(named: text(entry["default_reasoning_level"]))
        let defaultEffort: ReasoningEffort
        if let declaredDefault, efforts.contains(declaredDefault) {
            defaultEffort = declaredDefault
        } else {
            defaultEffort = efforts[0]
            notes.append("默认推理档位不可用，改用 " + defaultEffort.rawValue)
        }

        let rawVisibility = text(entry["visibility"])
        let visibility: ModelVisibility
        if let parsed = ModelVisibility(rawValue: rawVisibility.lowercased()) {
            visibility = parsed
        } else {
            visibility = .list
            notes.append("可见性无法识别，按「在模型列表中显示」处理")
        }

        let model = ModelConfiguration(
            slug: slug,
            displayName: displayName,
            modelDescription: description,
            contextWindow: contextWindow,
            maxContextWindow: maxContextWindow,
            supportedReasoningEfforts: efforts,
            defaultReasoningEffort: defaultEffort,
            visibility: visibility,
            priority: priority
        )
        return ImportedModel(model: model, notes: notes)
    }

    // MARK: - Merging into a provider

    /// What adding imported models to a provider's list did.
    public struct MergeResult: Equatable, Sendable {
        public var models: [ModelConfiguration]
        /// Slugs that were not previously present.
        public var added: [String]
        /// Slugs that replaced an existing model of the same name.
        public var overwritten: [String]

        public init(models: [ModelConfiguration], added: [String], overwritten: [String]) {
            self.models = models
            self.added = added
            self.overwritten = overwritten
        }
    }

    /// Adds imported models to an existing list, keeping the user's list intact.
    ///
    /// A slug that is already there is replaced **in place**, keeping the existing entry's
    /// identity, so an expanded card does not collapse and the model being edited does not lose
    /// focus. Two entries can never share a slug: the generator refuses a catalog with duplicate
    /// slugs, so "keep both" is not an option. Priorities are renumbered over the result, because
    /// the generator writes its own `1000 + position` and the stored numbers only carry order.
    public static func merge(
        imported: [ModelConfiguration],
        into existing: [ModelConfiguration]
    ) -> MergeResult {
        var models = existing
        var added: [String] = []
        var overwritten: [String] = []
        for model in imported {
            if let index = models.firstIndex(where: { $0.slug == model.slug }) {
                var replacement = model
                replacement.id = models[index].id
                models[index] = replacement
                overwritten.append(model.slug)
            } else {
                models.append(model)
                added.append(model.slug)
            }
        }
        for index in models.indices {
            models[index].priority = index + 1
        }
        return MergeResult(models: models, added: added, overwritten: overwritten)
    }

    // MARK: - Value reading

    private static func text(_ any: Any?) -> String {
        (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func effort(named raw: String) -> ReasoningEffort? {
        ReasoningEffort(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Accepts a number or a numeric string, because catalogs are written by several tools.
    private static func int(_ any: Any?) -> Int? {
        switch any {
        case let value as Int: return value
        case let value as Double: return Int(value)
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }
}
