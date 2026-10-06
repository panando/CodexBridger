import SwiftUI
import CodexBridgerCore

/// The scrollable part of the configuration form, without the ScrollView.
///
/// Split out so the form can be rendered headlessly: ImageRenderer gives a ScrollView no
/// intrinsic height, so rendering the whole screen produced a blank body.
public struct ProviderFormBody: View {
    @ObservedObject private var model: AppModel
    @Binding private var draft: ProviderDraft

    public init(model: AppModel, draft: Binding<ProviderDraft>) {
        self.model = model
        self._draft = draft
    }

    public var body: some View {
        VStack(spacing: Metrics.sectionSpacing) {
            identitySection
            credentialSection
            mappingSection
        }
        .padding()
    }

    // MARK: - 提供商信息

    private var identitySection: some View {
        SectionCard(model.t("提供商信息")) {
            if isActive { Pill(model.t("当前已激活"), tone: .success) }
        } content: {

            FormRow(model.t("名称"), info: "只影响这个窗口里显示的名字", isRequired: true) {
                ValueTextField(
                    text: $draft.provider.name,
                    isInvalid: hasError(.name),
                    monospaced: false,
                    accessibilityLabel: "名称"
                )
                if let issue = firstIssue(.name) { issueView(issue) }
            }

            FormRow(model.t("标识符"), info: "会成为 config.toml 里的 [model_providers.<标识符>]，也要做文件名，所以不能有点号和空格",
                    isRequired: true) {
                ValueTextField(text: $draft.provider.id, isInvalid: hasError(.identifier), accessibilityLabel: "标识符")
                if let issue = firstIssue(.identifier) { issueView(issue) }
            }

            FormRow(model.t("Base URL"), info: "第三方服务的 API 地址", isRequired: true) {
                ValueTextField(text: $draft.provider.baseURL, isInvalid: hasError(.baseURL), accessibilityLabel: "Base URL")
                if let issue = firstIssue(.baseURL) { issueView(issue) }
            }
        }
    }

    // MARK: - 认证

    private var credentialSection: some View {
        SectionCard(model.t("认证")) {
            EmptyView()
        } content: {

            FormRow(model.t("认证方式"), isRequired: true) {
                SelectField(
                    options: ProviderCredentialMode.allCases.map {
                        SelectField<ProviderCredentialMode>.Option(
                            value: $0,
                            title: $0.displayName
                        )
                    },
                    selection: $draft.provider.credentialMode,
                    isInvalid: hasError(.credential),
                    accessibilityLabel: "认证方式"
                )
            }

            switch provider.credentialMode {
            case .none:
                note("适用于本机服务等自带认证的情况，不会写入任何凭据字段。")
            case .bearerToken:
                FormRow(model.t("API Key"), info: "写入 experimental_bearer_token，同时合并进 auth.json", isRequired: true) {
                    FieldWithIssue(issue: firstIssue(.credential)) {
                        SecretTextField(
                            text: $draft.provider.bearerToken,
                            isInvalid: hasError(.credential),
                            accessibilityLabel: "API Key"
                        )
                    }
                }
            case .environmentKey:
                FormRow(model.t("环境变量名"), info: "ChatGPT 会从启动进程的环境里读这个变量", isRequired: true) {
                    FieldWithIssue(issue: firstIssue(.credential)) {
                        ValueTextField(text: $draft.provider.environmentKeyName, accessibilityLabel: "环境变量名")
                    }
                }
                // Wording follows the official reference, which describes this key as
                // "Optional setup guidance for the provider API key".
                FormRow(model.t("提示说明"), info: "env_key_instructions：给这个供应商的 API Key 写的设置指引。留空即可，ChatGPT 不需要它也能工作。") {
                    ValueTextField(
                        text: $draft.provider.environmentKeyInstructions,
                        monospaced: false,
                        accessibilityLabel: "环境变量提示说明"
                    )
                }
            case .command:
                FormRow(model.t("命令"), info: "这个命令需要把 token 打印到标准输出", isRequired: true) {
                    FieldWithIssue(issue: firstIssue(.credential)) {
                        ValueTextField(text: $draft.provider.commandAuth.command, accessibilityLabel: "取 token 的命令")
                    }
                }
                FormRow(model.t("参数"), info: "每行一个参数") {
                    ValueTextField(
                        text: commandArgsBinding,
                        monospaced: true,
                        accessibilityLabel: "命令参数",
                        lineRange: 2...5
                    )
                }
                FormRow(model.t("超时 (ms)")) {
                    OptionalIntField(value: $draft.provider.commandAuth.timeoutMs, accessibilityLabel: "命令超时")
                }
                FormRow(model.t("工作目录")) {
                    FolderPathField(
                        path: Binding(
                            get: { draft.provider.commandAuth.cwd ?? "" },
                            set: { draft.provider.commandAuth.cwd = $0.isEmpty ? nil : $0 }
                        ),
                        accessibilityLabel: "命令工作目录"
                    )
                }
            }

            // Codex treats the two credential strategies as mutually exclusive, so offering this
            // switch while the token comes from an external command would only invite a config it
            // refuses. The switch is simply absent in that mode; the help text does not need to
            // talk about a mode the user is not looking at, and saying so read as a contradiction
            // next to a switch that was plainly visible.
            if draft.provider.credentialMode != .command {
                ToggleRow(
                    model.t("当作 OpenAI 官方端点处理"),
                    info: "requires_openai_auth：打开后，ChatGPT 会把这个供应商当成 OpenAI 官方端点来请求，而不是第三方服务。",
                    isOn: $draft.provider.requiresOpenAIAuth
                )
            }
        }
    }

    // MARK: - 模型映射

    private var mappingSection: some View {
        SectionCard(model.t("模型配置")) {
            ActionLink(model.t("添加模型"), systemImage: "plus") { model.addModelToDraft() }
        } content: {

            if provider.models.isEmpty {
                emptyMappingHint
            } else {
                ForEach(Array(provider.models.enumerated()), id: \.element.id) { index, entry in
                    ProviderMappingCard(
                        model: entry,
                        isVisible: visibilityBinding(for: entry),
                        issues: draft.issues.filter { $0.field == .models && $0.subject == entry.slug },
                        isExpanded: expansionBinding(for: entry),
                        slug: modelTextBinding(for: entry, \.slug),
                        displayName: modelTextBinding(for: entry, \.displayName),
                        defaultReasoningEffort: modelValueBinding(for: entry, \.defaultReasoningEffort),
                        visibility: modelValueBinding(for: entry, \.visibility),
                        priority: modelTextBinding(for: entry, \.priority),
                        supportedReasoningEfforts: modelEffortsBinding(for: entry),
                        contextWindow: modelTextBinding(for: entry, \.contextWindow),
                        maxContextWindow: modelTextBinding(for: entry, \.maxContextWindow),
                        contextLabel: model.t("上下文"),
                        canMoveUp: index > 0,
                        canMoveDown: index < provider.models.count - 1,
                        onMoveUp: { model.moveModelInDraft(entry.id, by: -1) },
                        onMoveDown: { model.moveModelInDraft(entry.id, by: 1) },
                        onEdit: { model.editingModelID = entry.id },
                        onDelete: { model.removeModelFromDraft(entry.id) }
                    )
                }
            }

            if let issue = draft.issue(for: .models), provider.models.isEmpty {
                issueView(issue)
            }
        }
    }

    private var emptyMappingHint: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            LabelColumnSpacer()
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("还没有模型")
                    .font(Typography.control)
                    .foregroundStyle(Color.token(Palette.textPrimary))
                HelpText("加上模型后，ChatGPT 里才能选到它。模型名要填服务商文档里的那个名字。")
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.token(Palette.border), style: StrokeStyle(lineWidth: Metrics.borderWidth, dash: [4, 4]))
        )
    }

    // MARK: - Helpers

    private var provider: ProviderConfiguration { draft.provider }

    private var isActive: Bool { model.configuration.activeProviderID == draft.original.id }

    private func hasError(_ field: ProviderField) -> Bool {
        draft.issue(for: field)?.severity == .error
    }

    private func firstIssue(_ field: ProviderField) -> FieldIssue? {
        draft.issue(for: field)
    }

    /// A binding for any single-value model field.
    private func modelValueBinding<Value>(
        for entry: ModelConfiguration,
        _ keyPath: WritableKeyPath<ModelConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { draft.provider.models.first { $0.id == entry.id }?[keyPath: keyPath]
                ?? entry[keyPath: keyPath] },
            set: { newValue in
                guard let index = draft.provider.models.firstIndex(where: { $0.id == entry.id })
                else { return }
                draft.provider.models[index][keyPath: keyPath] = newValue
            }
        )
    }

    /// The set of reasoning levels a model offers. Never empty: turning the last one off would
    /// leave Codex with no level to switch between.
    private func modelEffortsBinding(for entry: ModelConfiguration) -> Binding<Set<ReasoningEffort>> {
        Binding(
            get: { draft.provider.models.first { $0.id == entry.id }?.supportedReasoningEfforts
                .reduce(into: Set<ReasoningEffort>()) { $0.insert($1) } ?? [] },
            set: { newValue in
                guard let index = draft.provider.models.firstIndex(where: { $0.id == entry.id })
                else { return }
                var levels = newValue.sorted()
                if levels.isEmpty {
                    levels = draft.provider.models[index].supportedReasoningEfforts
                }
                draft.provider.models[index].supportedReasoningEfforts = levels
                if !levels.contains(draft.provider.models[index].defaultReasoningEffort),
                   let first = levels.first {
                    draft.provider.models[index].defaultReasoningEffort = first
                }
            }
        )
    }

    /// A text binding for one numeric-or-string field of a model in the draft, so the mapping
    /// card can edit the model in place. Empty or unparsable text leaves the stored value alone
    /// rather than writing zero, which would silently destroy a valid setting.
    private func modelTextBinding(
        for entry: ModelConfiguration,
        _ keyPath: WritableKeyPath<ModelConfiguration, String>
    ) -> Binding<String> {
        Binding(
            get: { draft.provider.models.first { $0.id == entry.id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let index = draft.provider.models.firstIndex(where: { $0.id == entry.id })
                else { return }
                draft.provider.models[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func modelTextBinding(
        for entry: ModelConfiguration,
        _ keyPath: WritableKeyPath<ModelConfiguration, Int>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = draft.provider.models.first(where: { $0.id == entry.id })?[keyPath: keyPath]
                else { return "" }
                return String(value)
            },
            set: { newValue in
                guard let index = draft.provider.models.firstIndex(where: { $0.id == entry.id }),
                      let parsed = Int(newValue.trimmingCharacters(in: .whitespaces)), parsed > 0
                else { return }
                draft.provider.models[index][keyPath: keyPath] = parsed
            }
        )
    }

    /// An explicit `return` here disables the result builder — the compiler warns that
    /// "application of result builder 'ViewBuilder' disabled by explicit 'return' statement" —
    /// and the enclosing `Group` added nothing, so both are gone.
    @ViewBuilder
    private func issueView(_ issue: FieldIssue) -> some View {
        // Warnings generated by the guard carry a host or a URL, so they are resolved through
        // `warning(_:language:)` rather than the plain lookup table.
        let message = Localization.warning(issue.message, language: model.configuration.interfaceLanguage)
        if issue.severity == .error {
            InlineError(model.t(issue.message))
        } else {
            InlineWarning(message)
        }
    }

    @ViewBuilder
    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            LabelColumnSpacer()
            HelpText(text)
            Spacer(minLength: 0)
        }
    }

    private var commandArgsBinding: Binding<String> {
        Binding(
            get: { draft.provider.commandAuth.args.joined(separator: TOMLDocument.newline) },
            set: { newValue in
                draft.provider.commandAuth.args = newValue
                    .split(separator: Character(TOMLDocument.newline))
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func visibilityBinding(for entry: ModelConfiguration) -> Binding<Bool> {
        Binding(
            get: {
                draft.provider.models.first { $0.id == entry.id }?.visibility == .list
            },
            set: { isVisible in
                guard let index = draft.provider.models.firstIndex(where: { $0.id == entry.id }) else {
                    return
                }
                draft.provider.models[index].visibility = isVisible ? .list : .hide
            }
        )
    }

    private func expansionBinding(for entry: ModelConfiguration) -> Binding<Bool> {
        Binding(
            get: { model.expandedModelIDs.contains(entry.id) },
            set: { isExpanded in
                if isExpanded {
                    model.expandedModelIDs.insert(entry.id)
                } else {
                    model.expandedModelIDs.remove(entry.id)
                }
            }
        )
    }
}

/// One form section drawn as a card.
///
/// APIBypass wraps every section in `.padding()` + `controlBackgroundColor` +
/// `.cornerRadius(8)`, so the form sits as white cards on the window background rather than
/// as bare text on white.
public struct SectionCard<Content: View>: View {
    private let title: String
    private let trailing: AnyView?
    private let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = nil
        self.content = content()
    }

    public init<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing,
                               @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = AnyView(trailing())
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionInnerSpacing) {
            SectionCaption(title) {
                if let trailing { trailing }
            }
            VStack(spacing: Metrics.rowSpacing) {
                content
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.sectionCardRadius)
                .fill(Color.token(Palette.surface))
        )
    }
}
/// A control plus its validation message, stacked so the message sits directly under the
/// control and lines up with its left edge.
struct FieldWithIssue<Content: View>: View {
    private let issue: FieldIssue?
    private let content: Content

    init(issue: FieldIssue?, @ViewBuilder content: () -> Content) {
        self.issue = issue
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            content
            if let issue {
                if issue.severity == .error {
                    InlineError(issue.message)
                } else {
                    InlineWarning(issue.message)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
/// Optional integer entry used by the command-auth rows.
struct OptionalIntField: View {
    @Binding var value: Int?
    let accessibilityLabel: String

    var body: some View {
        ValueTextField(
            text: Binding(
                get: { value.map(String.init) ?? "" },
                set: { value = Int($0.trimmingCharacters(in: .whitespaces)) }
            ),
            prompt: "不写入",
            accessibilityLabel: accessibilityLabel
        )
        .frame(maxWidth: 200)
    }
}
