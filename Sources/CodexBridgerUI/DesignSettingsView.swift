import AppKit
import SwiftUI
import CodexBridgerCore

/// Global settings that apply regardless of which provider is active.
///
/// Every change is persisted immediately. Previously the pane only saved when the
/// window closed, so a setting could be lost by quitting from the menu bar.
public struct DesignSettingsView: View {
    @ObservedObject private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Card(model.t("模型推理"), subtitle: "对应 config.toml 的顶层字段，选「不写入」表示沿用 ChatGPT 默认值") {
                    FormRow(model.t("model_reasoning_effort")) {
                        SelectField(
                            options: [
                                .init(value: ReasoningEffort?.none, title: "不写入")
                            ] + ReasoningEffort.all.map {
                                SelectField<ReasoningEffort?>.Option(
                                    value: ReasoningEffort?.some($0),
                                    title: $0.rawValue
                                )
                            },
                            selection: $model.configuration.modelReasoningEffort,
                            accessibilityLabel: "model_reasoning_effort"
                        )
                        .frame(maxWidth: 220)
                    }
                    FormRow(model.t("model_reasoning_summary")) {
                        SelectField(
                            options: [
                                .init(value: ReasoningSummary?.none, title: "不写入")
                            ] + ReasoningSummary.allCases.map {
                                SelectField<ReasoningSummary?>.Option(
                                    value: ReasoningSummary?.some($0),
                                    title: $0.rawValue
                                )
                            },
                            selection: $model.configuration.modelReasoningSummary,
                            accessibilityLabel: "model_reasoning_summary"
                        )
                        .frame(maxWidth: 220)
                    }
                    FormRow(model.t("model_verbosity")) {
                        SelectField(
                            options: [
                                .init(value: ModelVerbosity?.none, title: "不写入")
                            ] + ModelVerbosity.allCases.map {
                                SelectField<ModelVerbosity?>.Option(
                                    value: ModelVerbosity?.some($0),
                                    title: $0.rawValue
                                )
                            },
                            selection: $model.configuration.modelVerbosity,
                            accessibilityLabel: "model_verbosity"
                        )
                        .frame(maxWidth: 220)
                    }
                    FormRow(model.t("model_supports_reasoning_summaries")) {
                        TriStateBoolField(
                            value: $model.configuration.modelSupportsReasoningSummaries,
                            accessibilityLabel: "model_supports_reasoning_summaries"
                        )
                    }
                }

                Card(model.t("模型参数模板"), subtitle: "生成模型参数文件时复制的结构来自哪里") {
                    FormRow(model.t("模板 slug"), help: "优先从本机 ChatGPT 的内置模型目录中取同名模型作为模板") {
                        ValueTextField(
                            text: $model.configuration.catalogTemplateSlug,
                            accessibilityLabel: "模板 slug"
                        )
                    }
                    FormRow(model.t("当前可用来源")) {
                        HStack(spacing: Spacing.sm) {
                            Text(model.templateSourceDescription)
                                .font(Typography.help)
                                .foregroundStyle(Color.token(Palette.textHelp))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(model.templateSourceDescription)
                            Spacer(minLength: 0)
                            Button("重新检测") { model.resolveTemplateSource() }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .hitTarget()
                        }
                    }
                    HelpText("模板只提供字段结构，不会把模板模型暴露给用户。")
                }

                Card(model.t("目录")) {
                    StateRow("ChatGPT 目录", model.paths.codexHome.path)
                    StateRow("config.toml", model.paths.configTOML.path)
                    StateRow("auth.json", model.paths.authJSON.path)
                    StateRow("模型参数目录", model.paths.modelCatalogsDirectory.path)
                    StateRow("备份目录", model.paths.backupDirectory.path)
                    StateRow("本软件配置", model.paths.appConfiguration.path)
                    HStack(spacing: Spacing.sm) {
                        Button("打开 ChatGPT 目录") { NSWorkspace.shared.open(model.paths.codexHome) }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .hitTarget()
                        Button("打开备份目录") { NSWorkspace.shared.open(model.paths.backupDirectory) }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .hitTarget()
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .onChange(of: model.configuration, initial: false) { _, _ in
            model.persist()
        }
    }
}
