import SwiftUI
import CodexBridgerCore

/// The global settings screen: the config.toml keys that belong to no provider.
///
/// It edits a draft and writes on demand, like the provider screen: the change ends up in the
/// file the product reads, so it is never applied while the user is still typing.
public struct GlobalSettingsView: View {
    @ObservedObject private var model: AppModel
    /// 审批与沙箱 opens by default because it holds the approval and sandbox choices; 推理可见性
    /// is left closed, by request.
    @State private var expanded: Set<GlobalSetting.Group> = [.approvalsAndSandbox]

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // The page title, not a section caption: this is what the screen is, so it
                    // takes the section-title size and the primary colour rather than the small
                    // grey used for group headings inside the cards.
                    Text(model.t("全局配置"))
                        .font(Typography.sectionTitle)
                        .foregroundStyle(Color.token(Palette.textPrimary))
                    HelpText(model.t("配置 config.toml 中的相应字段。mcp_servers / plugins / desktop 等设置不会在这里显示，也不会被改动。"))
                    ForEach(GlobalSetting.Group.displayOrder, id: \.self) { group in
                        let rows = settings(in: group)
                        if !rows.isEmpty {
                            groupCard(group) {
                                ForEach(rows, id: \.key) { setting in
                                    row(for: setting)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)
            }
            conflictBar
            actionBar
        }
        .background(Color.token(Palette.windowBackground))
        .onAppear {
            if model.globalSettingsStates.isEmpty { model.loadGlobalSettings() }
        }
    }

    // MARK: - Rows

    private func settings(in group: GlobalSetting.Group) -> [GlobalSetting] {
        GlobalSettingsCatalog.settings.filter { $0.group == group }
    }

    @ViewBuilder
    private func row(for setting: GlobalSetting) -> some View {
        // The label is the key itself: it is the name that appears in config.toml. The explanation
        // lives behind the info badge and nowhere else — a caption under every row doubled the
        // page height and said the same thing twice (2026-10-08, eighth review).
        FormRow(
            setting.key,
            // The text goes through the translation table, so a Chinese interface shows Chinese
            // explanations rather than the English official quotes (2026-10-08, seventh review).
            info: model.t(setting.detail),
            labelWidth: Metrics.settingsLabelWidth
        ) {
            control(for: setting)
        }
    }

    @ViewBuilder
    private func control(for setting: GlobalSetting) -> some View {
        switch setting.control {
        case .toggle:
            // A switch, not a checkbox: the rest of the app uses switches for binary choices,
            // and a checkbox in a column of text fields reads like a list item.
            Toggle("", isOn: flagBinding(for: setting))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(setting.key)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .choice(values):
            SelectField(
                options: values.map { SelectField<String>.Option(value: $0, title: $0) },
                selection: choiceBinding(for: setting, values: values),
                accessibilityLabel: setting.key
            )
        case .integer:
            CommittingField(
                text: numberText(for: setting),
                prompt: "",
                accessibilityLabel: setting.key,
                onCommit: { text in
                    guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else { return }
                    model.setGlobalSetting(.number(value), for: setting.key)
                }
            )
        case .stringArray:
            CommittingField(
                text: listText(for: setting),
                prompt: "",
                accessibilityLabel: setting.key,
                onCommit: { text in
                    let items = text.split(separator: Character("\n"), omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    model.setGlobalSetting(.list(items), for: setting.key)
                }
            )
        case .text:
            ValueTextField(
                text: textBinding(for: setting),
                monospaced: false,
                accessibilityLabel: setting.key
            )
        }
    }

    // MARK: - Bindings

    /// The value to show: the pending edit if there is one, otherwise what the file holds.
    private func shown(_ setting: GlobalSetting) -> SettingValue? {
        if let change = model.globalSettingPendingChange(for: setting.key) {
            switch change {
            case let .write(value): return value
            case .remove: return nil
            }
        }
        if case let .value(_, parsed)? = model.globalSettingsStates[setting.key] { return parsed }
        return nil
    }

    private func flagBinding(for setting: GlobalSetting) -> Binding<Bool> {
        Binding(
            get: {
                if case let .flag(value)? = shown(setting) { return value }
                return false
            },
            set: { model.setGlobalSetting(.flag($0), for: setting.key) }
        )
    }

    private func choiceBinding(for setting: GlobalSetting, values: [String]) -> Binding<String> {
        Binding(
            get: {
                if case let .choice(value)? = shown(setting), values.contains(value) { return value }
                return values.first ?? ""
            },
            set: { model.setGlobalSetting(.choice($0), for: setting.key) }
        )
    }

    private func textBinding(for setting: GlobalSetting) -> Binding<String> {
        Binding(
            get: {
                if case let .text(value)? = shown(setting) { return value }
                return ""
            },
            set: { model.setGlobalSetting(.text($0), for: setting.key) }
        )
    }

    private func numberText(for setting: GlobalSetting) -> Binding<String> {
        Binding(
            get: {
                if case let .number(value)? = shown(setting) { return String(value) }
                return ""
            },
            set: { _ in }
        )
    }

    private func listText(for setting: GlobalSetting) -> Binding<String> {
        Binding(
            get: {
                if case let .list(items)? = shown(setting) { return items.joined(separator: "\n") }
                return ""
            },
            set: { _ in }
        )
    }

    /// One group drawn as a white card on the window background, matching the provider form's
    /// section cards, with the caption doubling as the collapse control.
    ///
    /// The frame is the point: without it a run of rows reads as one long list and the group
    /// headings are just text sitting between fields.
    private func groupCard<Content: View>(
        _ group: GlobalSetting.Group,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isExpanded = expanded.contains(group)
        return VStack(alignment: .leading, spacing: 0) {
            // The padding sits inside the header and inside the body, rather than around the card
            // as a whole, which is what lets the header's hit area reach both card edges. See
            // `CollapsibleCardHeader`.
            CollapsibleCardHeader(
                title: model.t(group.displayName),
                isExpanded: isExpanded,
                accessibilityValue: model.t(isExpanded ? "已展开" : "已折叠"),
                onToggle: { toggle(group) }
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    content()
                }
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.bottom, Metrics.cardPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.sectionCardRadius)
                .fill(Color.token(Palette.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.sectionCardRadius)
                .strokeBorder(Color.token(Palette.border), lineWidth: Metrics.borderWidth)
        )
        .animation(.easeOut(duration: Motion.appear), value: isExpanded)
    }

    private func toggle(_ group: GlobalSetting.Group) {
        if expanded.contains(group) { expanded.remove(group) } else { expanded.insert(group) }
    }

    // MARK: - Bars

    @ViewBuilder
    private var conflictBar: some View {
        if !model.globalSettingsConflicts.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Divider()
                HelpText(model.t("这些参数刚被别的程序改了，没有写入任何东西："))
                ForEach(model.globalSettingsConflicts, id: \.key) { conflict in
                    HelpText(
                        conflict.key + model.t("：载入时是 ") + (conflict.loadedRaw ?? model.t("未设置"))
                            + model.t("，现在是 ") + (conflict.currentRaw ?? model.t("已删除"))
                        , lineLimit: 2
                    )
                }
                HStack(spacing: Spacing.md) {
                    Button(model.t("用我的值覆盖")) {
                        model.updateGlobalConfiguration(acceptingConflicts: true)
                    }
                    .buttonStyle(.bordered)
                    Button(model.t("放弃这些键，其余照写")) { model.dropConflictingChanges() }
                        .buttonStyle(.bordered)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.sm)
            .background(Color.token(Palette.surface))
        }
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Spacing.md) {
                if let notice = model.globalSettingsNotice {
                    StatusBanner(kind: bannerKind(notice.kind), message: notice.message)
                }
                Spacer(minLength: Spacing.md)
                Button(model.t("重置")) { model.resetGlobalSettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!model.globalSettingsIsDirty)
                Button(model.t("更新配置")) { model.updateGlobalConfiguration() }
                    .controlSize(.large)
                    .modifier(ProminentWhileEnabled(isEnabled: canUpdate))
                    .disabled(!canUpdate)
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Metrics.actionBarVerticalPadding)
            .frame(height: Metrics.actionBarHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.token(Palette.surface))
    }

    private var canUpdate: Bool {
        model.globalSettingsIsDirty && model.globalSettingsConflicts.isEmpty
    }

    private func bannerKind(_ kind: AppModel.GlobalSettingsNotice.Kind) -> StatusBanner.Kind {
        switch kind {
        case .success: return .success
        case .warning: return .warning
        case .failure: return .failure
        }
    }
}

/// Emphasised only while it can be used, matching the provider screen's action bar.
private struct ProminentWhileEnabled: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// A field that keeps what is being typed locally and reports it when the user is done.
///
/// Committing on every keystroke would push half-typed numbers into the draft, so the field
/// keeps its own text and commits on submit or when it loses focus.
struct CommittingField: View {
    @State private var text: String
    private let prompt: String
    private let accessibilityLabel: String
    private let onCommit: (String) -> Void
    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>,
        prompt: String,
        accessibilityLabel: String,
        onCommit: @escaping (String) -> Void
    ) {
        self._text = State(initialValue: text.wrappedValue)
        self.prompt = prompt
        self.accessibilityLabel = accessibilityLabel
        self.onCommit = onCommit
    }

    var body: some View {
        ValueTextField(
            text: $text,
            prompt: prompt,
            monospaced: true,
            accessibilityLabel: accessibilityLabel
        )
        .focused($isFocused)
        .onSubmit { onCommit(text) }
        .onChange(of: isFocused) { _, focused in
            if !focused { onCommit(text) }
        }
    }
}
