import AppKit
import SwiftUI
import CodexBridgerCore

/// Shows what Codex currently has on disk, plus where CodexBridger stores things.
///
/// Labels and values share the same fixed label column as every other row, so the
/// panel no longer needed its own hand-tuned 130pt column that clipped long labels.
public struct CodexStatePanel: View {
    @ObservedObject private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Card(model.t("ChatGPT 当前状态"), subtitle: model.paths.codexHome.path) {
            if let error = model.loadErrorMessage {
                InlineError("读取已保存的 CodexBridger 配置失败：" + error)
            }
            let snapshot = model.snapshot
            StateRow("config.toml", snapshot.configExists ? "存在" : "不存在")
            StateRow("model_provider", snapshot.modelProviderID ?? "—")
            StateRow("model", snapshot.modelSlug ?? "—")
            StateRow("model_catalog_json", snapshot.modelCatalogJSON ?? "—")
            StateRow("模型参数文件", snapshot.catalogFileExists ? "存在" : "缺失")
            StateRow("已定义提供商",
                     snapshot.providerIDs.isEmpty ? "—" : snapshot.providerIDs.joined(separator: ", "))
            StateRow("模板来源", model.templateSourceDescription)
            StateRow("本软件配置", model.paths.appConfiguration.path)
            if !model.authKeyNames.isEmpty {
                StateRow("auth.json 键", model.authKeyNames.joined(separator: ", "))
            }
            HStack(spacing: Spacing.sm) {
                Button("刷新") { model.refreshCodexState() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .hitTarget()
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
}

/// Read-only key/value row aligned to the shared label column.
struct StateRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        FormRow(label) {
            Text(value)
                .font(Typography.monoSmall)
                .foregroundStyle(Color.token(Palette.textPrimary))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
