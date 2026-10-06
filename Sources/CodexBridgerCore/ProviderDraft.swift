import Foundation

// MARK: - Draft editing
//
// The reference screen edits a provider in place. CodexBridger cannot do that literally:
// a provider change ends up in ~/.codex/config.toml, which Codex is reading. So edits go
// into a draft, the draft explains what is wrong, and nothing is written until the user
// applies it.

/// A field the form can attach a message to.
public enum ProviderField: String, CaseIterable, Sendable {
    case identifier
    case name
    case baseURL
    case credential
    case models

    /// Label shown next to the control, matching the reference layout.
    public var label: String {
        switch self {
        case .identifier: return "标识符"
        case .name: return "名称"
        case .baseURL: return "Base URL"
        case .credential: return "认证"
        case .models: return "模型映射"
        }
    }
}

public struct FieldIssue: Equatable, Sendable {
    public enum Severity: Equatable, Sendable {
        case error
        case warning
    }

    public let field: ProviderField
    public let severity: Severity
    public let message: String
    /// Model slug the message is about, when the field is `.models`.
    public let subject: String?

    public init(
        field: ProviderField,
        severity: Severity,
        message: String,
        subject: String? = nil
    ) {
        self.field = field
        self.severity = severity
        self.message = message
        self.subject = subject
    }
}

/// Thrown by `ProviderDraft.commit()` so a caller cannot write an invalid provider.
public struct ValidationFailure: Error, Equatable, Sendable {
    public let issues: [FieldIssue]

    public init(issues: [FieldIssue]) {
        self.issues = issues
    }

    public var message: String {
        issues.map(\.message).joined(separator: "；")
    }
}

/// Prevents a double submit while a write is in flight.
public struct SubmitGate: Equatable, Sendable {
    public private(set) var inFlight = false
    /// How many times a submit was accepted, for tests and diagnostics.
    public private(set) var accepted = 0

    public init() {}

    /// Returns false when a submission is already running, so the caller must not start
    /// a second write. This is what stops a double click from writing Codex config twice.
    public mutating func begin() -> Bool {
        guard !inFlight else { return false }
        inFlight = true
        accepted += 1
        return true
    }

    public mutating func end() {
        inFlight = false
    }

    public mutating func reset() {
        inFlight = false
    }
}

/// A provider being edited, with its validation state.
public struct ProviderDraft: Equatable, Sendable {
    /// Working copy. Bind the form straight to this.
    public var provider: ProviderConfiguration
    /// The value loaded from disk, used for dirty tracking and Reset.
    public let original: ProviderConfiguration
    /// Ids already taken by other providers, so a rename cannot collide.
    public var existingIDs: Set<String>
    /// True when this provider has never been saved.
    /// Smallest context window Codex accepts for a model. A new model starts here, so adding
    /// one produces something that can actually be saved.
    public static let minimumContextWindow = 1_024

    public let isNew: Bool

    public init(
        provider: ProviderConfiguration,
        existingIDs: Set<String> = [],
        isNew: Bool = false
    ) {
        self.provider = provider
        self.original = provider
        self.existingIDs = existingIDs
        self.isNew = isNew
    }

    // MARK: - Dirty tracking

    /// A provider that is not on disk yet is always unsaved, even before it is edited.
    ///
    /// Without this, a provider created from the picker reported "no changes" and Save stayed
    /// disabled, so it could never be written at all.
    public var isDirty: Bool { isNew || provider != original }

    public mutating func reset() {
        provider = original
    }

    // MARK: - Validation

    public var issues: [FieldIssue] { ProviderValidator.issues(for: provider,
                                                              originalID: original.id,
                                                              existingIDs: existingIDs) }

    public var errors: [FieldIssue] { issues.filter { $0.severity == .error } }
    public var warnings: [FieldIssue] { issues.filter { $0.severity == .warning } }

    public var canSave: Bool { errors.isEmpty }

    public func issue(for field: ProviderField) -> FieldIssue? {
        errors.first { $0.field == field } ?? warnings.first { $0.field == field }
    }

    /// Every model-level message, so the mapping list can show them per row.
    public func issues(forModelSlug slug: String) -> [FieldIssue] {
        issues.filter { $0.field == .models && $0.subject == slug }
    }

    // MARK: - Commit

    /// Returns the normalised provider, or throws while anything is invalid.
    public func commit() throws -> ProviderConfiguration {
        let blocking = errors
        guard blocking.isEmpty else { throw ValidationFailure(issues: blocking) }
        return ProviderValidator.normalised(provider)
    }
}

// MARK: - Validator

enum ProviderValidator {

    /// Smallest context window Codex accepts for a model. A new model starts here so it is
    /// always valid enough to save.
    static let minimumContextWindow = ProviderDraft.minimumContextWindow

    static func issues(
        for provider: ProviderConfiguration,
        originalID: String,
        existingIDs: Set<String>
    ) -> [FieldIssue] {
        var issues: [FieldIssue] = []
        issues.append(contentsOf: identifierIssues(provider, originalID: originalID,
                                                   existingIDs: existingIDs))
        issues.append(contentsOf: nameIssues(provider))
        issues.append(contentsOf: baseURLIssues(provider))
        issues.append(contentsOf: credentialIssues(provider))
        issues.append(contentsOf: modelIssues(provider))
        return issues
    }

    private static func identifierIssues(
        _ provider: ProviderConfiguration,
        originalID: String,
        existingIDs: Set<String>
    ) -> [FieldIssue] {
        let id = provider.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            return [FieldIssue(field: .identifier, severity: .error,
                               message: "标识符不能为空，它会成为 config.toml 里的 [model_providers.<标识符>]")]
        }
        if !ProviderConfiguration.isValidIdentifier(id) {
            return [FieldIssue(field: .identifier, severity: .error,
                               message: "只能用字母、数字、下划线和连字符，最多 64 个字符（不能有点号或空格）")]
        }
        if id != originalID, existingIDs.contains(id) {
            return [FieldIssue(field: .identifier, severity: .error,
                               message: "已经有另一个提供商叫 " + id + "，标识符不能重复")]
        }
        return []
    }

    private static func nameIssues(_ provider: ProviderConfiguration) -> [FieldIssue] {
        guard provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return [FieldIssue(field: .name, severity: .error, message: "名称不能为空")]
    }

    private static func baseURLIssues(_ provider: ProviderConfiguration) -> [FieldIssue] {
        let raw = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return [FieldIssue(field: .baseURL, severity: .error, message: "Base URL 不能为空")]
        }
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              !(url.host ?? "").isEmpty else {
            return [FieldIssue(field: .baseURL, severity: .error,
                               message: "需要完整地址，例如 https://api.example.com/v1")]
        }
        // A local address is legitimate, it just cannot work unless that server is up.
        return ActivationGuard.baseURLWarnings(raw).map {
            FieldIssue(field: .baseURL, severity: .warning, message: $0)
        }
    }

    private static func credentialIssues(_ provider: ProviderConfiguration) -> [FieldIssue] {
        switch provider.credentialMode {
        case .none:
            return []
        case .bearerToken:
            guard provider.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            return [FieldIssue(field: .credential, severity: .error,
                               message: "这个认证方式需要一个 Bearer Token")]
        case .environmentKey:
            guard provider.environmentKeyName
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            return [FieldIssue(field: .credential, severity: .error,
                               message: "这个认证方式需要填环境变量名，ChatGPT 会从进程环境里读它")]
        case .command:
            var issues: [FieldIssue] = []
            if provider.commandAuth.command
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(FieldIssue(field: .credential, severity: .error,
                                         message: "这个认证方式需要填一个能打印 token 的命令"))
            }
            if provider.requiresOpenAIAuth {
                issues.append(FieldIssue(
                    field: .credential, severity: .error,
                    message: "ChatGPT 规定 .auth 命令方式不能和 requires_openai_auth 同时使用，请二选一"
                ))
            }
            return issues
        }
    }

    private static func modelIssues(_ provider: ProviderConfiguration) -> [FieldIssue] {
        if provider.models.isEmpty {
            return [FieldIssue(
                field: .models, severity: .warning,
                message: "还没有模型。加上模型后，ChatGPT 里才能选到它。"
            )]
        }
        var issues: [FieldIssue] = []
        var seen = Set<String>()
        for model in provider.models {
            let slug = model.slug.trimmingCharacters(in: .whitespacesAndNewlines)
            if slug.isEmpty {
                issues.append(FieldIssue(field: .models, severity: .error,
                                         message: "模型名不能为空", subject: model.slug))
                continue
            }
            if !seen.insert(slug).inserted {
                issues.append(FieldIssue(field: .models, severity: .error,
                                         message: "模型名重复：" + slug, subject: slug))
                continue
            }
            if model.contextWindow < minimumContextWindow {
                issues.append(FieldIssue(
                    field: .models, severity: .error,
                    message: "上下文窗口至少 " + String(minimumContextWindow), subject: slug
                ))
            }
            if model.maxContextWindow < model.contextWindow {
                issues.append(FieldIssue(
                    field: .models, severity: .error,
                    message: "max_context_window 不能小于 context_window", subject: slug
                ))
            }
            if !model.supportedReasoningEfforts.contains(model.defaultReasoningEffort) {
                issues.append(FieldIssue(
                    field: .models, severity: .error,
                    message: "默认推理强度 " + model.defaultReasoningEffort.rawValue
                        + " 不在勾选的档位里",
                    subject: slug
                ))
            }
        }
        return issues
    }

    /// Trims user input so a stray space never reaches config.toml.
    static func normalised(_ provider: ProviderConfiguration) -> ProviderConfiguration {
        var result = provider
        result.id = provider.id.trimmingCharacters(in: .whitespacesAndNewlines)
        result.name = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.baseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        result.bearerToken = provider.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        result.environmentKeyName = provider.environmentKeyName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        result.environmentKeyInstructions = provider.environmentKeyInstructions
            .trimmingCharacters(in: .whitespacesAndNewlines)
        result.commandAuth.command = provider.commandAuth.command
            .trimmingCharacters(in: .whitespacesAndNewlines)
        result.commandAuth.args = provider.commandAuth.args
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let cwd = provider.commandAuth.cwd?
            .trimmingCharacters(in: .whitespacesAndNewlines), cwd.isEmpty {
            result.commandAuth.cwd = nil
        }
        result.models = provider.models.map { model in
            var copy = model
            copy.slug = model.slug.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.displayName = model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }
        return result
    }
}
