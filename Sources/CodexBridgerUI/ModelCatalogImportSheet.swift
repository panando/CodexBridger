import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CodexBridgerCore

/// Imports models from an existing model catalog file.
///
/// Two ways in, because the file comes from two different places: something the user was given,
/// or a catalog already sitting in this machine's Codex home. Either way the file is parsed before
/// anything is applied, and the user picks which models to bring over — a catalog can hold a dozen
/// models the user does not want in this provider.
public struct ModelCatalogImportSheet: View {

    public struct Confirmation {
        public var outcome: ModelCatalogImporter.ImportOutcome
        public var slugs: Set<String>

        public init(outcome: ModelCatalogImporter.ImportOutcome, slugs: Set<String>) {
            self.outcome = outcome
            self.slugs = slugs
        }
    }

    private let title: String
    private let catalogsDirectory: URL
    private let existingSlugs: Set<String>
    /// A file to read as soon as the sheet appears.
    ///
    /// Only the screenshot trigger uses this: Accessibility permission is not granted, so a
    /// script cannot click "选择文件…" and the checklist would otherwise never be inspectable.
    private let initialFile: URL?
    private let onConfirm: (Confirmation) -> Void
    private let onCancel: () -> Void

    @State private var outcome: ModelCatalogImporter.ImportOutcome?
    @State private var selected: Set<String> = []
    @State private var errorMessage: String?
    @State private var sourceName: String = ""
    @State private var localFiles: [LocalCatalogFile] = []

    public init(
        title: String,
        catalogsDirectory: URL,
        existingSlugs: Set<String>,
        initialFile: URL? = nil,
        onConfirm: @escaping (Confirmation) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.catalogsDirectory = catalogsDirectory
        self.existingSlugs = existingSlugs
        self.initialFile = initialFile
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
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
                    chooseFileCard
                    localFilesCard

                    if let errorMessage {
                        InlineError(errorMessage)
                    }
                    if let outcome {
                        selectionCard(outcome)
                    }
                }
                .padding(Spacing.xl)
            }

            Divider()

            HStack(spacing: Spacing.md) {
                if let outcome {
                    Text("已选 " + String(selected.count) + " / " + String(outcome.models.count) + " 个模型")
                        .font(Typography.help)
                        .foregroundStyle(Color.token(Palette.textHelp))
                }
                Spacer(minLength: 0)
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .hitTarget()
                Button("导入") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .hitTarget()
                    .disabled(selected.isEmpty)
            }
            .padding(Spacing.lg)
        }
        .frame(width: 620, height: 700)
        .background(Color.token(Palette.surface))
        .onAppear {
            reloadLocalFiles()
            if let initialFile { load(initialFile) }
        }
    }

    // MARK: - Sources

    private var chooseFileCard: some View {
        Card("从文件选择", subtitle: "挑一个别人给你的，或者你自己保存的模型参数文件") {
            HStack(spacing: Spacing.md) {
                Button("选择文件…") { chooseFile() }
                    .buttonStyle(.bordered)
                    .hitTarget()
                if !sourceName.isEmpty {
                    Text(sourceName)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Color.token(Palette.textSecondary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var localFilesCard: some View {
        Card("这台机器上已有的模型参数文件", subtitle: catalogsDirectory.path) {
            if localFiles.isEmpty {
                Text("这个目录里没有 .json 文件")
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.textHelp))
            } else {
                ForEach(localFiles) { file in
                    Button { load(file.url) } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "doc.text")
                                .iconFont(.s)
                                .foregroundStyle(Color.token(Palette.textSecondary))
                            Text(file.name)
                                .font(Typography.control)
                                .foregroundStyle(Color.token(Palette.textPrimary))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: Spacing.sm)
                            Text(modelCountLabel(file))
                                .font(Typography.help)
                                .foregroundStyle(Color.token(Palette.textHelp))
                            Text(sizeLabel(file))
                                .font(Typography.help)
                                .foregroundStyle(Color.token(Palette.textHelp))
                        }
                        .padding(.vertical, Spacing.xxs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - The checklist

    private func selectionCard(_ outcome: ModelCatalogImporter.ImportOutcome) -> some View {
        Card("选择要导入的模型", subtitle: "同名的模型会被文件里的参数覆盖") {
            HStack(spacing: Spacing.md) {
                ActionLink("全选") { selected = Set(outcome.models.map(\.model.slug)) }
                ActionLink("全不选") { selected = [] }
                Spacer(minLength: 0)
                if !outcome.skipped.isEmpty {
                    Pill(String(outcome.skipped.count) + " 个被跳过", tone: .danger)
                }
            }

            ForEach(outcome.models, id: \.model.id) { imported in
                row(imported)
            }

            if !outcome.notes.isEmpty {
                HelpText(outcome.notes.joined(separator: " "))
            }
            if !outcome.skipped.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(Array(outcome.skipped.enumerated()), id: \.offset) { _, skip in
                        Text("跳过 " + (skip.slug ?? "（无模型 ID）") + "：" + skip.reason)
                            .font(Typography.help)
                            .foregroundStyle(Color.token(Palette.danger))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func row(_ imported: ModelCatalogImporter.ImportedModel) -> some View {
        let model = imported.model
        return HStack(alignment: .top, spacing: Spacing.sm) {
            CheckboxControl(
                isOn: binding(for: model.slug),
                accessibilityLabel: "导入 " + model.slug
            )
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.sm) {
                    Text(model.slug)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Color.token(Palette.textPrimary))
                    if existingSlugs.contains(model.slug) {
                        Pill("已存在 · 会覆盖", tone: .danger)
                    }
                    if model.visibility == .hide {
                        Pill("隐藏", tone: .neutral)
                    }
                    Spacer(minLength: 0)
                }
                Text(description(for: model))
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.textHelp))
                    .lineLimit(2)
                if !imported.notes.isEmpty {
                    Text(imported.notes.joined(separator: "；"))
                        .font(Typography.help)
                        .foregroundStyle(Color.token(Palette.warning))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func description(for model: ModelConfiguration) -> String {
        let efforts = model.supportedReasoningEfforts.map(\.rawValue).joined(separator: "/")
        return model.displayName + " · 上下文 " + String(model.contextWindow)
            + " · " + efforts
    }

    private func binding(for slug: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(slug) },
            set: { isOn in
                if isOn { selected.insert(slug) } else { selected.remove(slug) }
            }
        )
    }

    // MARK: - Loading

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "读取"
        panel.message = "选择一个模型参数文件（{ \"models\": [ … ] }）"
        if panel.runModal() == .OK, let url = panel.url {
            load(url)
        }
    }

    private func load(_ url: URL) {
        sourceName = url.lastPathComponent
        do {
            let data = try Data(contentsOf: url)
            let parsed = try ModelCatalogImporter.parse(data: data)
            outcome = parsed
            errorMessage = nil
            // Nothing is selected to begin with: a catalog commonly holds more models than the
            // user wants here, and importing by default would be a surprise.
            selected = []
        } catch {
            outcome = nil
            selected = []
            errorMessage = error.localizedDescription
        }
    }

    private func reloadLocalFiles() {
        localFiles = ModelCatalogFiles.list(in: catalogsDirectory)
    }

    private func confirm() {
        guard let outcome, !selected.isEmpty else { return }
        onConfirm(Confirmation(outcome: outcome, slugs: selected))
    }

    // MARK: - Labels

    private func modelCountLabel(_ file: LocalCatalogFile) -> String {
        guard let count = file.modelCount else { return "无法解析" }
        return String(count) + " 个模型"
    }

    private func sizeLabel(_ file: LocalCatalogFile) -> String {
        let kilobytes = Double(file.byteCount) / 1024
        return String(format: "%.0f KB", kilobytes)
    }
}
