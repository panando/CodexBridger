import SwiftUI
import CodexBridgerCore

/// Parameter editor for a single model.
///
/// Only parameters a Codex model catalog actually accepts are exposed: the context
/// window, the advertised reasoning levels, visibility and ordering.
public struct ModelEditorSheet: View {
    @State private var draft: ModelConfiguration
    private let onSave: (ModelConfiguration) -> Void
    private let onCancel: () -> Void

    public init(
        model: ModelConfiguration,
        onSave: @escaping (ModelConfiguration) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._draft = State(initialValue: model)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var hasContextWarning: Bool { draft.maxContextWindow < draft.contextWindow }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("模型参数")
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Color.token(Palette.textPrimary))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Card("标识", subtitle: "slug 是第三方服务真实接受的模型名，会写入 config.toml 的 model") {
                        FormRow("模型 ID", isRequired: true) {
                            ValueTextField(text: $draft.slug, monospaced: true, accessibilityLabel: "模型 ID")
                        }
                        FormRow("显示名称") {
                            ValueTextField(text: $draft.displayName, accessibilityLabel: "显示名称")
                        }
                        FormRow("描述") {
                            ValueTextField(
                                text: $draft.modelDescription,
                                monospaced: false,
                                accessibilityLabel: "模型描述"
                            )
                        }
                    }

                    Card("上下文") {
                        FormRow("context_window", isRequired: true) {
                            IntEntry(value: $draft.contextWindow, accessibilityLabel: "context_window")
                        }
                        FormRow("max_context_window") {
                            IntEntry(value: $draft.maxContextWindow, accessibilityLabel: "max_context_window")
                        }
                        if hasContextWarning {
                            InlineError("max_context_window 小于 context_window，写入时会自动抬到相同值")
                        }
                    }

                    Card("推理强度", subtitle: "ChatGPT 只会在勾选的档位之间切换") {
                        FormRow("支持的档位") {
                            EffortGrid(
                                selected: $draft.supportedReasoningEfforts
                            )
                        }
                        FormRow("默认档位") {
                            SelectField(
                                options: availableEfforts.map {
                                    SelectField<ReasoningEffort>.Option(
                                        value: $0,
                                        title: $0.rawValue
                                    )
                                },
                                selection: $draft.defaultReasoningEffort,
                                accessibilityLabel: "默认推理强度"
                            )
                            .frame(maxWidth: 220)
                        }
                    }

                    Card("其它") {
                        FormRow("可见性") {
                            SelectField(
                                options: [
                                    .init(value: ModelVisibility.list, title: "在模型列表中显示"),
                                    .init(value: ModelVisibility.hide, title: "隐藏")
                                ],
                                selection: $draft.visibility,
                                accessibilityLabel: "可见性"
                            )
                            .frame(maxWidth: 260)
                        }
                        FormRow("排序 priority", help: "数字越小越靠前") {
                            IntEntry(value: $draft.priority, accessibilityLabel: "排序 priority")
                        }
                    }
                }
                .padding(Spacing.xl)
            }

            Divider()

            HStack(spacing: Spacing.md) {
                Spacer(minLength: 0)
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .hitTarget()
                Button("保存") {
                    var final = draft
                    if final.maxContextWindow < final.contextWindow {
                        final.maxContextWindow = final.contextWindow
                    }
                    if final.supportedReasoningEfforts.isEmpty {
                        final.supportedReasoningEfforts = [final.defaultReasoningEffort]
                    }
                    if !final.supportedReasoningEfforts.contains(final.defaultReasoningEffort) {
                        final.defaultReasoningEffort = final.supportedReasoningEfforts[0]
                    }
                    onSave(final)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .hitTarget()
                .disabled(draft.slug.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Spacing.lg)
        }
        .frame(width: 560, height: 680)
    }

    private var availableEfforts: [ReasoningEffort] {
        draft.supportedReasoningEfforts.isEmpty
            ? ReasoningEffort.all
            : draft.supportedReasoningEfforts
    }
}

/// Integer entry with a stable width so the column never jitters.
struct IntEntry: View {
    @Binding var value: Int
    let accessibilityLabel: String

    var body: some View {
        ValueTextField(
            text: Binding(
                get: { String(value) },
                set: { value = Int($0.trimmingCharacters(in: .whitespaces)) ?? value }
            ),
            accessibilityLabel: accessibilityLabel
        )
        .frame(maxWidth: 180)
    }
}

/// Reasoning levels laid out on a grid so every checkbox column lines up.
struct EffortGrid: View {
    @Binding var selected: [ReasoningEffort]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.xs) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        if index < ReasoningEffort.all.count {
                            let effort = ReasoningEffort.all[index]
                            HStack(spacing: Spacing.xs) {
                                CheckboxControl(
                                    isOn: binding(for: effort),
                                    accessibilityLabel: effort.rawValue
                                )
                                Text(effort.rawValue)
                                    .font(Typography.control)
                                    .foregroundStyle(Color.token(Palette.textPrimary))
                            }
                        } else {
                            Color.clear.frame(width: 1, height: 1)
                        }
                    }
                }
            }
        }
    }

    private func binding(for effort: ReasoningEffort) -> Binding<Bool> {
        Binding(
            get: { selected.contains(effort) },
            set: { isOn in
                var set = Set(selected)
                if isOn { set.insert(effort) } else { set.remove(effort) }
                selected = ReasoningEffort.all.filter { set.contains($0) }
            }
        )
    }
}
