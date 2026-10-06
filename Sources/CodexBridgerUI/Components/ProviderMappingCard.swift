import SwiftUI
import CodexBridgerCore

// MARK: - Reference controls
//
// Shapes measured from the APIBypass reference screens: mapping cards are a bordered
// rounded rectangle with the toggle on the left, a status dot, a two-line title block, and
// a trailing disclosure; section actions are borderless blue text links.

/// Borderless blue text button, used for "新建提供商" and "+ 添加映射".
public struct ActionLink: View {
    private let title: String
    private let systemImage: String?
    private let isEnabled: Bool
    private let action: () -> Void

    @State private var interaction = ControlInteractionState()
    @FocusState private var isFocused: Bool

    public init(
        _ title: String,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage).iconFont(.s, weight: .semibold)
                }
                Text(title).font(Typography.control)
            }
            .foregroundStyle(isEnabled
                             ? Color.token(Palette.accentText)
                             : Color.token(Palette.textHelp))
            .padding(.horizontal, Spacing.sm)
            .frame(height: Metrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(interaction.phase == .hovered || interaction.phase == .focusedHovered
                          ? Color.token(Palette.hoverFill)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .focused($isFocused)
        .help(title)
        .onHover { interaction.send($0 ? .hoverEnter : .hoverExit) }
        .onChange(of: isFocused) { _, focused in
            interaction.send(focused ? .focusGain : .focusLoss)
        }
        .focusRing(isFocused, cornerRadius: Radius.sm)
    }
}

/// A toggle with its label to the right, an optional info badge, and no left column label.
///
/// The reference uses this shape for its settings toggles.
public struct ToggleRow: View {
    private let title: String
    private let info: String?
    @Binding private var isOn: Bool
    private let isEnabled: Bool
    private let onChange: ((Bool) -> Void)?

    public init(
        _ title: String,
        info: String? = nil,
        isOn: Binding<Bool>,
        isEnabled: Bool = true,
        onChange: ((Bool) -> Void)? = nil
    ) {
        self.title = title
        self.info = info
        self._isOn = isOn
        self.isEnabled = isEnabled
        self.onChange = onChange
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Metrics.labelToControlGap) {
            LabelColumnSpacer()
            HStack(spacing: Spacing.sm) {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!isEnabled)
                    .onChange(of: isOn) { _, value in onChange?(value) }
                Text(title)
                    .font(Typography.control)
                    .foregroundStyle(Color.token(Palette.textPrimary))
                if let info { InfoBadge(info) }
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: Metrics.rowHeight)
        .accessibilityElement(children: .combine)
    }
}

/// Masked field, matching the reference API Key row: a bare SecureField that spans the whole
/// control column. APIBypass has no reveal button beside it, and adding one shortened the field
/// relative to every other row.
public struct SecretTextField: View {
    @Binding private var text: String
    private let isEnabled: Bool
    private let isInvalid: Bool
    private let accessibilityLabel: String

    public init(
        text: Binding<String>,
        isEnabled: Bool = true,
        isInvalid: Bool = false,
        accessibilityLabel: String
    ) {
        self._text = text
        self.isEnabled = isEnabled
        self.isInvalid = isInvalid
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        SecureField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(Typography.mono)
            .lineLimit(1)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(Color.token(Palette.danger), lineWidth: Metrics.borderWidth)
                    .opacity(isInvalid ? 1 : 0)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!isEnabled)
            .accessibilityLabel(accessibilityLabel)
            .frame(minHeight: Metrics.rowHeight)
    }
}

/// One model mapping row, matching the reference card.
public struct ProviderMappingCard: View {
    private let model: ModelConfiguration
    @Binding private var isVisible: Bool
    private let issues: [FieldIssue]
    @Binding private var isExpanded: Bool
    /// Inline editing: the expanded rows edit the model in place instead of opening a sheet.
    private let slug: Binding<String>
    private let displayName: Binding<String>
    private let defaultReasoningEffort: Binding<ReasoningEffort>
    private let visibility: Binding<ModelVisibility>
    private let priority: Binding<String>
    private let supportedReasoningEfforts: Binding<Set<ReasoningEffort>>

    /// Levels offered in the default-effort dropdown, lowest to highest.
    private var reasoningOptions: [SelectField<ReasoningEffort>.Option] {
        ReasoningEffort.all.map { .init(value: $0, title: $0.rawValue) }
    }
    private let contextWindow: Binding<String>
    private let maxContextWindow: Binding<String>
    /// Word for "context", resolved by the caller: this card holds a model value, not the app
    /// model, so it cannot look strings up itself.
    private let contextLabel: String
    private let canMoveUp: Bool
    private let canMoveDown: Bool
    private let onMoveUp: () -> Void
    private let onMoveDown: () -> Void
    private let onEdit: () -> Void
    private let onDelete: () -> Void

    @State private var isHovered = false

    public init(
        model: ModelConfiguration,
        isVisible: Binding<Bool>,
        issues: [FieldIssue] = [],
        isExpanded: Binding<Bool>,
        slug: Binding<String>,
        displayName: Binding<String>,
        defaultReasoningEffort: Binding<ReasoningEffort>,
        visibility: Binding<ModelVisibility>,
        priority: Binding<String>,
        supportedReasoningEfforts: Binding<Set<ReasoningEffort>>,
        contextWindow: Binding<String>,
        maxContextWindow: Binding<String>,
        contextLabel: String = "上下文",
        canMoveUp: Bool,
        canMoveDown: Bool,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.model = model
        self._isVisible = isVisible
        self.issues = issues
        self._isExpanded = isExpanded
        self.slug = slug
        self.displayName = displayName
        self.defaultReasoningEffort = defaultReasoningEffort
        self.visibility = visibility
        self.priority = priority
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.contextWindow = contextWindow
        self.maxContextWindow = maxContextWindow
        self.contextLabel = contextLabel
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    private var title: String {
        model.displayName.isEmpty ? model.slug : model.displayName
    }

    private var hasError: Bool { issues.contains { $0.severity == .error } }

    /// Second line. The reference shows a source to target mapping; CodexBridger has no
    /// renaming step, so it shows the slug Codex will receive plus its size.
    private var summary: String {
        model.slug + "  ·  " + contextLabel + " " + ProviderMappingCard.compact(model.contextWindow)
    }

    static func compact(_ value: Int) -> String {
        guard value >= 1_000 else { return String(value) }
        let thousands = Double(value) / 1_000
        return thousands == thousands.rounded()
            ? String(Int(thousands)) + "K"
            : String(format: "%.1fK", thousands)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Metrics.cardHeaderSpacing) {
                Toggle("", isOn: $isVisible)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("在 ChatGPT 模型列表里显示 " + model.slug)

                Circle()
                    .fill(isVisible ? Color.token(Palette.success) : Color.token(Palette.textHelp))
                    .frame(width: Metrics.statusDotSize, height: Metrics.statusDotSize)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.control)
                        .foregroundStyle(Color.token(Palette.textPrimary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(summary)
                        .font(Typography.help)
                        .monospaced()
                        .foregroundStyle(Color.token(Palette.textHelp))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(summary)
                }
                Spacer(minLength: Spacing.sm)

                Menu {
                    Button("上移", action: onMoveUp).disabled(!canMoveUp)
                    Button("下移", action: onMoveDown).disabled(!canMoveDown)
                    Divider()
                    Button("删除", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .iconFont(.s, weight: .semibold)
                        .foregroundStyle(Color.token(Palette.textSecondary))
                        .frame(width: Metrics.iconChrome + 8, height: Metrics.iconChrome)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多操作")

                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .iconFont(.s, weight: .semibold)
                        .foregroundStyle(Color.token(Palette.textSecondary))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .frame(width: Metrics.iconChrome + 8, height: Metrics.iconChrome)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起模型参数" : "展开模型参数")
            }
            // Clicking the header row does the same thing as clicking the chevron.
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Divider()
                    // The model id is the field Codex actually matches on: it is the
                    // catalog slug and the value written to `model` in config.toml. The binding
                    // was already plumbed in but nothing rendered it, so the id could only be
                    // inherited from a preset and never typed.
                    FormRow("模型 ID", info: "ChatGPT 识别这个模型用的名字，也是写进 config.toml 的 model 值", isRequired: true) {
                        ValueTextField(text: slug, monospaced: true,
                                       accessibilityLabel: "模型 ID")
                    }
                    FormRow("显示名称") {
                        ValueTextField(text: displayName, monospaced: false,
                                       accessibilityLabel: "显示名称")
                    }
                    FormRow("上下文窗口") {
                        ValueTextField(text: contextWindow, monospaced: true,
                                       accessibilityLabel: "上下文窗口")
                    }
                    FormRow("最大上下文") {
                        ValueTextField(text: maxContextWindow, monospaced: true,
                                       accessibilityLabel: "最大上下文窗口")
                    }
                    FormRow("可用推理强度") {
                        HStack(spacing: Spacing.sm) {
                            ForEach(ReasoningEffort.all, id: \.rawValue) { level in
                                let isOn = supportedReasoningEfforts.wrappedValue
                                    .contains(level)
                                Button {
                                    var next = supportedReasoningEfforts.wrappedValue
                                    if next.contains(level) {
                                        next.remove(level)
                                    } else {
                                        next.insert(level)
                                    }
                                    // The default must stay one of the offered levels.
                                    if !next.contains(defaultReasoningEffort.wrappedValue),
                                       let first = next.sorted().first {
                                        defaultReasoningEffort.wrappedValue = first
                                    }
                                    supportedReasoningEfforts.wrappedValue = next
                                } label: {
                                    Text(level.rawValue)
                                        .font(Typography.help)
                                        .foregroundStyle(Color.token(
                                            isOn ? Palette.textOnAccent : Palette.textSecondary))
                                        .padding(.horizontal, Spacing.sm)
                                        .frame(minWidth: 44, minHeight: Metrics.minDenseHitTarget)
                                        .background(
                                            RoundedRectangle(cornerRadius: Radius.xs)
                                                .fill(Color.token(
                                                    isOn ? Palette.accent : Palette.surfaceSunken)))
                                }
                                .buttonStyle(.plain)
                                .help(isOn ? "点击取消该档位" : "点击启用该档位")
                            }
                        }
                    }
                    FormRow("默认推理强度") {
                        SelectField(
                            options: reasoningOptions,
                            selection: defaultReasoningEffort,
                            accessibilityLabel: "默认推理强度")
                    }
                    FormRow("模型列表") {
                        SelectField(
                            options: [
                                .init(value: ModelVisibility.list, title: "显示"),
                                .init(value: ModelVisibility.hide, title: "隐藏")
                            ],
                            selection: visibility,
                            accessibilityLabel: "模型列表可见性")
                    }
                    FormRow("排序 priority", info: "数字越小越靠前") {
                        ValueTextField(text: priority, monospaced: true,
                                       accessibilityLabel: "排序")
                            .frame(maxWidth: 120)
                    }
                }
            }

            if !issues.isEmpty {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    LabelColumnSpacer()
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            if issue.severity == .error {
                                InlineError(issue.message)
                            } else {
                                InlineWarning(issue.message)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.cardPaddingHorizontal)
        .padding(.vertical, Metrics.cardPaddingVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Color.token(Palette.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(
                    hasError ? Color.token(Palette.danger)
                        : (isHovered ? Color.token(Palette.borderStrong) : Color.token(Palette.border)),
                    lineWidth: Metrics.borderWidth
                )
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: Motion.hover), value: isHovered)
        .accessibilityElement(children: .contain)
    }
}
